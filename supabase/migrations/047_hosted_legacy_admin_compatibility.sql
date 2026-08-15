-- Hosted legacy Admin compatibility layer
-- Purpose: allow the current fail-closed GitHub portals to converge onto the
-- existing Evolution Voucher hosted production schema without rewriting legacy
-- Voucher, redemption, Auth or Partner records.
--
-- This migration intentionally adapts the API boundary to the hosted lineage:
-- - hosted Admin identity lives in partner_users(role='admin')
-- - hosted Voucher states include valid/redeemed
-- - hosted redemption success state is success
-- - hosted vouchers do not carry a physical usage_limit column
--
-- Data policy: function/API compatibility only. No historical business row is
-- migrated or rewritten by this migration.

create or replace function public.current_operational_realm()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner public.partner_users%rowtype;
  v_staff public.staff_users%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('authenticated',false,'realm',null);
  end if;

  if exists (
    select 1
    from public.partner_users pu
    where pu.user_id=v_uid
      and lower(coalesce(pu.role,''))='admin'
      and lower(coalesce(pu.status,''))='active'
  ) then
    return jsonb_build_object(
      'authenticated',true,
      'realm','admin',
      'user_id',v_uid
    );
  end if;

  select pu.* into v_partner
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and lower(coalesce(pu.role,'')) in ('partner_admin','partner_staff')
    and lower(coalesce(pu.status,''))='active'
    and pu.removed_at is null
    and lower(coalesce(p.status,''))='active'
  limit 1;

  if found then
    return jsonb_build_object(
      'authenticated',true,
      'realm','partner',
      'user_id',v_uid,
      'partner_id',v_partner.partner_id,
      'role',v_partner.role
    );
  end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid
    and lower(coalesce(su.status,''))='active'
  limit 1;

  if found then
    return jsonb_build_object(
      'authenticated',true,
      'realm','staff',
      'user_id',v_uid,
      'branch_id',v_staff.branch_id,
      'role',v_staff.role
    );
  end if;

  return jsonb_build_object(
    'authenticated',true,
    'realm',null,
    'user_id',v_uid
  );
end;
$$;
revoke all on function public.current_operational_realm() from public, anon;
grant execute on function public.current_operational_realm() to authenticated;

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
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  select jsonb_build_object(
    'partners_total',(
      select count(*) from public.partners p
      where lower(coalesce(p.status,''))<>'archived'
    ),
    'partners_active',(
      select count(*) from public.partners p
      where lower(coalesce(p.status,''))='active'
    ),
    'vouchers_total',(select count(*) from public.vouchers),
    'vouchers_active',(
      select count(*) from public.vouchers v
      where lower(coalesce(v.status,'')) in ('valid','active')
        and v.expiry_date>=v_today
    ),
    'vouchers_redeemed',(
      select count(*) from public.vouchers v
      where lower(coalesce(v.status,''))='redeemed'
         or (
           coalesce(v.usage_count,0)>0
           and lower(coalesce(v.status,'')) not in ('revoked','expired')
         )
    ),
    'vouchers_expired',(
      select count(*) from public.vouchers v
      where lower(coalesce(v.status,''))='expired'
         or (
           lower(coalesce(v.status,'')) in ('valid','active')
           and v.expiry_date<v_today
         )
    ),
    'vouchers_revoked',(
      select count(*) from public.vouchers v
      where lower(coalesce(v.status,''))='revoked'
    ),
    'redemptions_completed',(
      select count(*) from public.redemptions r
      where lower(coalesce(r.status,'')) in ('success','completed')
    ),
    'redemptions_reversed',(
      select count(*) from public.redemptions r
      where lower(coalesce(r.status,''))='reversed'
    ),
    'redemptions_today',(
      select count(*) from public.redemptions r
      where lower(coalesce(r.status,'')) in ('success','completed')
        and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
    )
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;

create or replace function public.admin_voucher_report(
  p_partner_id uuid default null,
  p_limit integer default 500
)
returns table(
  voucher_id uuid,
  voucher_code text,
  partner_id uuid,
  partner_name text,
  customer_name text,
  customer_phone text,
  voucher_type text,
  voucher_status text,
  expiry_date date,
  issued_at timestamptz,
  issued_by_name text,
  usage_count integer,
  usage_limit integer,
  last_redeemed_at timestamptz,
  last_branch_name text,
  last_staff_name text,
  completed_redemptions bigint,
  reversed_redemptions bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;
  if p_limit is null or p_limit<1 or p_limit>5000 then
    raise exception 'Limit must be between 1 and 5000';
  end if;

  return query
  select
    v.id,
    v.voucher_code,
    v.partner_id,
    p.partner_name,
    v.customer_name,
    v.customer_phone,
    v.voucher_type,
    case
      when lower(coalesce(v.status,''))='revoked' then 'revoked'
      when lower(coalesce(v.status,''))='expired'
        or (lower(coalesce(v.status,'')) in ('valid','active')
            and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date)
        then 'expired'
      when lower(coalesce(v.status,''))='redeemed' or coalesce(v.usage_count,0)>0
        then 'redeemed'
      else 'active'
    end,
    v.expiry_date,
    v.issued_at,
    v.issued_by_name,
    greatest(coalesce(v.usage_count,0),case when lower(coalesce(v.status,''))='redeemed' then 1 else 0 end),
    1::integer,
    lr.redeemed_at,
    lr.branch_name,
    lr.staff_name_snapshot,
    coalesce(rc.completed_count,0),
    coalesce(rc.reversed_count,0)
  from public.vouchers v
  left join public.partners p on p.id=v.partner_id
  left join lateral (
    select r.redeemed_at,b.branch_name,r.staff_name_snapshot
    from public.redemptions r
    left join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id
      and lower(coalesce(r.status,'')) in ('success','completed')
    order by r.redeemed_at desc
    limit 1
  ) lr on true
  left join lateral (
    select
      count(*) filter (where lower(coalesce(r.status,'')) in ('success','completed'))::bigint as completed_count,
      count(*) filter (where lower(coalesce(r.status,''))='reversed')::bigint as reversed_count
    from public.redemptions r
    where r.voucher_id=v.id
  ) rc on true
  where p_partner_id is null or v.partner_id=p_partner_id
  order by v.issued_at desc nulls last
  limit p_limit;
end;
$$;
revoke all on function public.admin_voucher_report(uuid,integer) from public, anon;
grant execute on function public.admin_voucher_report(uuid,integer) to authenticated;

create or replace function public.admin_redemption_report(
  p_partner_id uuid default null,
  p_limit integer default 500
)
returns table(
  redemption_id uuid,
  voucher_id uuid,
  voucher_code text,
  partner_id uuid,
  partner_name text,
  branch_id uuid,
  branch_name text,
  staff_user_id uuid,
  staff_name text,
  redeem_method text,
  redemption_status text,
  redeemed_at timestamptz,
  notes text,
  reversed_at timestamptz,
  reversed_by_name text,
  reverse_reason text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;
  if p_limit is null or p_limit<1 or p_limit>5000 then
    raise exception 'Limit must be between 1 and 5000';
  end if;

  return query
  select
    r.id,
    r.voucher_id,
    v.voucher_code,
    coalesce(r.partner_id,v.partner_id),
    p.partner_name,
    r.branch_id,
    b.branch_name,
    r.staff_user_id,
    coalesce(r.staff_name_snapshot,su.staff_name),
    r.redeem_method,
    case
      when lower(coalesce(r.status,'')) in ('success','completed') then 'completed'
      when lower(coalesce(r.status,''))='reversed' then 'reversed'
      else lower(coalesce(r.status,''))
    end,
    r.redeemed_at,
    r.notes,
    r.reversed_at,
    r.reversed_by_name,
    r.reverse_reason
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  left join public.partners p on p.id=coalesce(r.partner_id,v.partner_id)
  left join public.branches b on b.id=r.branch_id
  left join public.staff_users su on su.id=r.staff_user_id
  where p_partner_id is null or coalesce(r.partner_id,v.partner_id)=p_partner_id
  order by r.redeemed_at desc nulls last
  limit p_limit;
end;
$$;
revoke all on function public.admin_redemption_report(uuid,integer) from public, anon;
grant execute on function public.admin_redemption_report(uuid,integer) to authenticated;

create or replace function public.admin_partner_directory()
returns table(
  partner_id uuid,
  partner_code text,
  partner_name text,
  partner_status text,
  voucher_limit integer,
  vouchers_issued bigint,
  staff_limit integer,
  partner_staff_count bigint,
  staff_access_enabled boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    p.id,
    p.partner_code,
    p.partner_name,
    p.status,
    p.voucher_limit,
    (select count(*) from public.vouchers v where v.partner_id=p.id),
    p.staff_limit,
    (select count(*)
       from public.partner_users pu
      where pu.partner_id=p.id
        and lower(coalesce(pu.role,''))='partner_staff'
        and pu.removed_at is null
        and lower(coalesce(pu.status,''))<>'removed'),
    p.staff_access_enabled
  from public.partners p
  where lower(coalesce(p.status,''))<>'archived'
  order by p.partner_name,p.partner_code;
end;
$$;
revoke all on function public.admin_partner_directory() from public, anon;
grant execute on function public.admin_partner_directory() to authenticated;

create or replace function public.admin_active_branches()
returns table(
  branch_id uuid,
  branch_code text,
  branch_name text,
  address text,
  phone text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select b.id,b.branch_code,b.branch_name,b.address,b.phone
  from public.branches b
  where lower(coalesce(b.status,''))='active'
  order by b.branch_name,b.branch_code;
end;
$$;
revoke all on function public.admin_active_branches() from public, anon;
grant execute on function public.admin_active_branches() to authenticated;

create or replace function public.admin_set_partner_status(
  p_partner_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_old_status text;
  v_new_status text := lower(trim(coalesce(p_status,'')));
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if v_new_status not in ('active','suspended','archived') then
    raise exception 'Invalid Partner status';
  end if;

  select p.status into v_old_status
  from public.partners p
  where p.id=p_partner_id
  for update;
  if not found then raise exception 'Partner not found'; end if;

  update public.partners
  set status=v_new_status
  where id=p_partner_id;

  insert into public.admin_audit_log(
    actor_user_id,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,'partner_status_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('status',v_old_status),
    jsonb_build_object('status',v_new_status),
    jsonb_build_object('source','hosted_legacy_admin_compatibility')
  );

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'status',v_new_status);
end;
$$;
revoke all on function public.admin_set_partner_status(uuid,text) from public, anon;
grant execute on function public.admin_set_partner_status(uuid,text) to authenticated;

create or replace function public.admin_set_partner_voucher_limit(
  p_partner_id uuid,
  p_voucher_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_old_limit integer;
  v_issued bigint;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_voucher_limit is null or p_voucher_limit<0 then
    raise exception 'Voucher limit must be zero or greater';
  end if;

  select p.voucher_limit into v_old_limit
  from public.partners p
  where p.id=p_partner_id
  for update;
  if not found then raise exception 'Partner not found'; end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.partner_id=p_partner_id;

  if p_voucher_limit<>0 and p_voucher_limit<v_issued then
    raise exception 'Voucher limit cannot be lower than vouchers already issued';
  end if;

  update public.partners
  set voucher_limit=p_voucher_limit
  where id=p_partner_id;

  insert into public.admin_audit_log(
    actor_user_id,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,'partner_voucher_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('voucher_limit',v_old_limit),
    jsonb_build_object('voucher_limit',p_voucher_limit,'issued_count',v_issued),
    jsonb_build_object('source','hosted_legacy_admin_compatibility')
  );

  return jsonb_build_object(
    'success',true,
    'partner_id',p_partner_id,
    'voucher_limit',p_voucher_limit,
    'vouchers_issued',v_issued
  );
end;
$$;
revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from public, anon;
grant execute on function public.admin_set_partner_voucher_limit(uuid,integer) to authenticated;

create or replace function public.admin_set_partner_staff_limit(
  p_partner_id uuid,
  p_staff_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_old_limit integer;
  v_staff_count bigint;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_staff_limit is null or p_staff_limit<0 or p_staff_limit>1000 then
    raise exception 'Staff limit must be between 0 and 1000';
  end if;

  select p.staff_limit into v_old_limit
  from public.partners p
  where p.id=p_partner_id
  for update;
  if not found then raise exception 'Partner not found'; end if;

  select count(*) into v_staff_count
  from public.partner_users pu
  where pu.partner_id=p_partner_id
    and lower(coalesce(pu.role,''))='partner_staff'
    and pu.removed_at is null
    and lower(coalesce(pu.status,''))<>'removed';

  if p_staff_limit<v_staff_count then
    raise exception 'Staff limit cannot be lower than existing non-removed Staff count';
  end if;

  update public.partners
  set staff_limit=p_staff_limit
  where id=p_partner_id;

  insert into public.admin_audit_log(
    actor_user_id,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,'partner_staff_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('staff_limit',v_old_limit),
    jsonb_build_object('staff_limit',p_staff_limit,'existing_staff_count',v_staff_count),
    jsonb_build_object('source','hosted_legacy_admin_compatibility')
  );

  return jsonb_build_object(
    'success',true,
    'partner_id',p_partner_id,
    'staff_limit',p_staff_limit,
    'staff_count',v_staff_count
  );
end;
$$;
revoke all on function public.admin_set_partner_staff_limit(uuid,integer) from public, anon;
grant execute on function public.admin_set_partner_staff_limit(uuid,integer) to authenticated;

comment on function public.current_operational_realm() is
'Hosted legacy realm adapter. Admin identity is sourced from active partner_users role=admin; active Partner realm also requires partners.status=active.';
comment on function public.admin_dashboard_summary() is
'Hosted legacy reporting adapter. Supports valid/redeemed Voucher states and success/completed redemption states without rewriting historical rows.';
