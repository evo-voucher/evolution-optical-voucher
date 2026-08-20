-- Unified current-record summary and stale-data cleanup.
-- Both the nightly cron wrapper and Admin wrapper call the same protected cleanup engine.

begin;

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select jsonb_build_object(
    'partners_total',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))<>'archived'),
    'partners_active',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))='active'),
    'vouchers_allocated',(select coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0) from public.partner_voucher_allocations a join public.partners p on p.id=a.partner_id where upper(coalesce(p.partner_code,''))<>'ADMIN'),
    'vouchers_issued',(select count(*) from public.vouchers v where v.issued_at is not null),
    'vouchers_total',(select count(*) from public.vouchers),
    'allocation_remaining',greatest(0,
      (select coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0) from public.partner_voucher_allocations a join public.partners p on p.id=a.partner_id where upper(coalesce(p.partner_code,''))<>'ADMIN')
      -(select count(*) from public.vouchers v where v.issued_at is not null)
    ),
    'vouchers_active',(select count(*) from public.vouchers v where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today),
    'vouchers_redeemed',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired'))),
    'vouchers_expired',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today)),
    'vouchers_revoked',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='revoked'),
    'redemptions_completed',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed')),
    'redemptions_reversed',(select count(*) from public.redemptions r where lower(coalesce(r.status,''))='reversed'),
    'redemptions_today',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed') and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public._cleanup_stale_voucher_data(
  p_retention_days integer default 30,
  p_actor_user_id uuid default null,
  p_source text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_now timestamptz := now();
  v_ids uuid[] := array[]::uuid[];
  v_count integer := 0;
  v_expired_count integer := 0;
  v_revoked_count integer := 0;
  v_alloc_ids uuid[] := array[]::uuid[];
  v_alloc_counts integer[] := array[]::integer[];
  v_allocations_adjusted integer := 0;
  v_allocation_units_removed integer := 0;
  v_before_qty integer;
  v_after_qty integer;
  v_stale_alloc_ids uuid[] := array[]::uuid[];
  v_stale_partner_ids uuid[] := array[]::uuid[];
  v_stale_template_ids uuid[] := array[]::uuid[];
  v_allocations_deleted integer := 0;
  v_access_deleted integer := 0;
  v_deleted_now integer := 0;
  v_i integer;
begin
  if p_retention_days is null or p_retention_days < 1 or p_retention_days > 3650 then
    raise exception 'Retention days must be between 1 and 3650';
  end if;

  select
    coalesce(array_agg(v.id),array[]::uuid[]),
    count(*) filter (
      where lower(coalesce(v.status,''))<>'revoked'
        and v.revoked_at is null
        and v.expiry_date is not null
        and v.expiry_date <= v_today - p_retention_days
    ),
    count(*) filter (
      where (lower(coalesce(v.status,''))='revoked' or v.revoked_at is not null)
        and coalesce(v.revoked_at,v.updated_at,v.created_at) <= v_now - make_interval(days=>p_retention_days)
    )
  into v_ids,v_expired_count,v_revoked_count
  from public.vouchers v
  where coalesce(v.usage_count,0)=0
    and not exists(select 1 from public.redemptions r where r.voucher_id=v.id)
    and (
      (
        (lower(coalesce(v.status,''))='revoked' or v.revoked_at is not null)
        and coalesce(v.revoked_at,v.updated_at,v.created_at) <= v_now - make_interval(days=>p_retention_days)
      )
      or
      (
        lower(coalesce(v.status,''))<>'revoked'
        and v.revoked_at is null
        and v.expiry_date is not null
        and v.expiry_date <= v_today - p_retention_days
      )
    );

  v_count := coalesce(array_length(v_ids,1),0);

  if v_count>0 then
    select
      coalesce(array_agg(x.allocation_id order by x.allocation_id),array[]::uuid[]),
      coalesce(array_agg(x.deleted_count::integer order by x.allocation_id),array[]::integer[])
    into v_alloc_ids,v_alloc_counts
    from (
      select v.allocation_id,count(*) as deleted_count
      from public.vouchers v
      where v.id=any(v_ids)
        and v.allocation_id is not null
      group by v.allocation_id
    ) x;

    delete from public.vouchers
    where id=any(v_ids)
      and coalesce(usage_count,0)=0
      and not exists(select 1 from public.redemptions r where r.voucher_id=vouchers.id);

    v_allocations_adjusted := coalesce(array_length(v_alloc_ids,1),0);
    if v_allocations_adjusted>0 then
      perform set_config('evo.hard_reduce_allowed','on',true);

      for v_i in 1..v_allocations_adjusted loop
        select a.quantity_allocated
          into v_before_qty
        from public.partner_voucher_allocations a
        where a.id=v_alloc_ids[v_i]
        for update;

        if found then
          update public.partner_voucher_allocations a
          set quantity_allocated = greatest(
                coalesce(a.quantity_revoked,0) + (
                  select count(*)::integer
                  from public.vouchers vx
                  where vx.allocation_id=a.id
                ),
                a.quantity_allocated-v_alloc_counts[v_i]
              ),
              updated_at = now()
          where a.id=v_alloc_ids[v_i]
          returning a.quantity_allocated into v_after_qty;

          v_allocation_units_removed :=
            v_allocation_units_removed + greatest(0,v_before_qty-v_after_qty);
        end if;
      end loop;

      perform set_config('evo.hard_reduce_allowed','off',true);

      delete from public.voucher_allocation_events e
      where e.allocation_id=any(v_alloc_ids);
    end if;
  end if;

  select
    coalesce(array_agg(a.id order by a.id),array[]::uuid[]),
    coalesce(array_agg(a.partner_id order by a.id),array[]::uuid[]),
    coalesce(array_agg(vv.template_id order by a.id),array[]::uuid[])
  into v_stale_alloc_ids,v_stale_partner_ids,v_stale_template_ids
  from public.partner_voucher_allocations a
  join public.voucher_versions vv on vv.id=a.version_id
  where not exists(select 1 from public.vouchers v where v.allocation_id=a.id)
    and (
      greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))=0
      or
      (a.valid_until is not null and a.valid_until <= v_now - make_interval(days=>p_retention_days))
    );

  if coalesce(array_length(v_stale_alloc_ids,1),0)>0 then
    delete from public.voucher_allocation_events e
    where e.allocation_id=any(v_stale_alloc_ids);

    delete from public.partner_voucher_allocations a
    where a.id=any(v_stale_alloc_ids)
      and not exists(select 1 from public.vouchers v where v.allocation_id=a.id)
      and (
        greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))=0
        or
        (a.valid_until is not null and a.valid_until <= v_now - make_interval(days=>p_retention_days))
      );
    get diagnostics v_allocations_deleted = row_count;

    for v_i in 1..coalesce(array_length(v_stale_partner_ids,1),0) loop
      delete from public.partner_voucher_access pva
      where pva.partner_id=v_stale_partner_ids[v_i]
        and pva.template_id=v_stale_template_ids[v_i]
        and pva.quota_type='allocation'
        and not exists(
          select 1
          from public.partner_voucher_allocations a
          join public.voucher_versions vv on vv.id=a.version_id
          where a.partner_id=pva.partner_id
            and vv.template_id=pva.template_id
        );
      get diagnostics v_deleted_now = row_count;
      v_access_deleted := v_access_deleted + v_deleted_now;
    end loop;
  end if;

  if v_count>0 or v_allocations_deleted>0 or v_access_deleted>0 then
    insert into public.admin_audit_log(
      actor_user_id,action_type,entity_type,entity_id,after_data,metadata
    ) values (
      p_actor_user_id,'stale_voucher_data_purged','voucher_cleanup',null,
      jsonb_build_object(
        'purged_vouchers',v_count,
        'expired_purged',v_expired_count,
        'revoked_purged',v_revoked_count,
        'allocations_adjusted',v_allocations_adjusted,
        'allocation_units_removed',v_allocation_units_removed,
        'allocations_deleted',v_allocations_deleted,
        'partner_access_deleted',v_access_deleted
      ),
      jsonb_build_object(
        'source',coalesce(nullif(trim(p_source),''),'system'),
        'retention_days',p_retention_days,
        'redeemed_history_protected',true,
        'remaining_stock_preserved',true
      )
    );
  end if;

  return jsonb_build_object(
    'success',true,
    'purged',v_count,
    'expired_purged',v_expired_count,
    'revoked_purged',v_revoked_count,
    'allocations_adjusted',v_allocations_adjusted,
    'allocation_units_removed',v_allocation_units_removed,
    'allocations_deleted',v_allocations_deleted,
    'partner_access_deleted',v_access_deleted,
    'retention_days',p_retention_days,
    'redeemed_history_protected',true,
    'remaining_stock_preserved',true
  );
end;
$$;

revoke all on function public._cleanup_stale_voucher_data(integer,uuid,text) from public;
revoke all on function public._cleanup_stale_voucher_data(integer,uuid,text) from anon;
revoke all on function public._cleanup_stale_voucher_data(integer,uuid,text) from authenticated;

create or replace function public.purge_unredeemed_vouchers(p_retention_days integer default 30)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_trusted_service_role() and session_user <> 'postgres' then
    raise exception 'Trusted server context required';
  end if;

  v_result := public._cleanup_stale_voucher_data(
    p_retention_days,
    null,
    'cron'
  );

  return coalesce((v_result->>'purged')::integer,0);
end;
$$;

create or replace function public.admin_purge_expired_unredeemed_vouchers(p_actor_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  if public.is_voucher_admin() then
    v_actor := auth.uid();
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  if not exists(
    select 1
    from public.admin_users a
    where a.user_id=v_actor and a.status='active'
  ) then
    raise exception 'Active Admin actor required';
  end if;

  return public._cleanup_stale_voucher_data(
    30,
    v_actor,
    'admin'
  );
end;
$$;

commit;
