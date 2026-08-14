-- Atomic Voucher Engine Admin mutations v1
-- Moves allocation/revocation/retirement state changes into PostgreSQL so
-- concurrency correctness does not depend on browser/Edge read-modify-write logic.

create or replace function public.admin_engine_allocate(
  p_partner_id uuid,
  p_version_id uuid,
  p_quantity integer,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_actor_name text;
  v_template_id uuid;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_created boolean := false;
begin
  if p_partner_id is null or p_version_id is null then raise exception 'Partner and Version are required'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be positive'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
  into v_actor_name
  from public.admin_users a
  where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
    raise exception 'Active Partner not found';
  end if;

  -- Serialize with issuance/retirement before checking Version status.
  -- This uses the same Version advisory-lock domain as migration 026/retirement.
  perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));

  select vv.template_id into v_template_id
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active';
  if not found then raise exception 'Active Voucher Version not found'; end if;

  -- Serialize first-allocation creation and increases for the same Partner+Version.
  perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_version_id::text,3301));

  select * into v_allocation
  from public.partner_voucher_allocations a
  where a.partner_id=p_partner_id
    and a.version_id=p_version_id
    and a.status='active'
  order by a.created_at desc
  limit 1
  for update;

  if found then
    update public.partner_voucher_allocations
    set quantity_allocated=quantity_allocated+p_quantity,
        updated_at=now()
    where id=v_allocation.id
    returning * into v_allocation;
  else
    insert into public.partner_voucher_allocations(
      partner_id,version_id,quantity_allocated,quantity_revoked,status,created_by
    ) values (
      p_partner_id,p_version_id,p_quantity,0,'active',v_actor
    ) returning * into v_allocation;
    v_created := true;
  end if;

  insert into public.partner_voucher_access(
    partner_id,template_id,status,quota_type,created_by,created_at,updated_at
  ) values (
    p_partner_id,v_template_id,'active','allocation',v_actor,now(),now()
  )
  on conflict(partner_id,template_id) do update
  set status='active',quota_type='allocation',updated_at=now();

  insert into public.voucher_allocation_events(
    allocation_id,partner_id,version_id,event_type,quantity,actor_user_id
  ) values (
    v_allocation.id,p_partner_id,p_version_id,
    case when v_created then 'allocated' else 'increased' end,
    p_quantity,v_actor
  );

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data
  ) values (
    v_actor,v_actor_name,'voucher_allocation_changed','voucher_allocation',v_allocation.id::text,p_partner_id,
    jsonb_build_object(
      'version_id',p_version_id,
      'quantity_added',p_quantity,
      'quantity_allocated',v_allocation.quantity_allocated,
      'quantity_revoked',v_allocation.quantity_revoked,
      'created',v_created
    )
  );

  return jsonb_build_object(
    'success',true,
    'allocation_id',v_allocation.id,
    'partner_id',p_partner_id,
    'version_id',p_version_id,
    'quantity_added',p_quantity,
    'quantity_allocated',v_allocation.quantity_allocated,
    'quantity_revoked',v_allocation.quantity_revoked,
    'created',v_created
  );
end;
$$;

revoke all on function public.admin_engine_allocate(uuid,uuid,integer,uuid) from public, anon;
grant execute on function public.admin_engine_allocate(uuid,uuid,integer,uuid) to authenticated, service_role;

create or replace function public.admin_engine_allocate_all(
  p_version_id uuid,
  p_quantity integer,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_partner record;
  v_count integer := 0;
begin
  if p_version_id is null then raise exception 'Version is required'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be positive'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  if not exists(select 1 from public.admin_users a where a.user_id=v_actor and a.status='active') then
    raise exception 'Active Admin actor required';
  end if;

  -- One database transaction: any failure rolls back every Partner allocation.
  for v_partner in
    select p.id from public.partners p where p.status='active' order by p.id
  loop
    perform public.admin_engine_allocate(v_partner.id,p_version_id,p_quantity,v_actor);
    v_count := v_count+1;
  end loop;

  return jsonb_build_object(
    'success',true,
    'version_id',p_version_id,
    'partners_allocated',v_count,
    'quantity_each',p_quantity
  );
end;
$$;

revoke all on function public.admin_engine_allocate_all(uuid,integer,uuid) from public, anon;
grant execute on function public.admin_engine_allocate_all(uuid,integer,uuid) to authenticated, service_role;

create or replace function public.admin_engine_revoke_unissued(
  p_allocation_id uuid,
  p_quantity integer,
  p_reason text default null,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_actor_name text;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_issued bigint;
  v_remaining bigint;
  v_next_revoked integer;
begin
  if p_allocation_id is null then raise exception 'Allocation is required'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be positive'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
  into v_actor_name
  from public.admin_users a
  where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  select * into v_allocation
  from public.partner_voucher_allocations a
  where a.id=p_allocation_id and a.status='active'
  for update;
  if not found then raise exception 'Active allocation not found'; end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.allocation_id=p_allocation_id;

  v_remaining := v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued;
  if p_quantity > v_remaining then
    raise exception 'Cannot revoke more than remaining unissued quantity';
  end if;

  v_next_revoked := v_allocation.quantity_revoked+p_quantity;
  update public.partner_voucher_allocations
  set quantity_revoked=v_next_revoked,updated_at=now()
  where id=p_allocation_id;

  insert into public.voucher_allocation_events(
    allocation_id,partner_id,version_id,event_type,quantity,reason,actor_user_id
  ) values (
    p_allocation_id,v_allocation.partner_id,v_allocation.version_id,'revoked',p_quantity,
    nullif(trim(coalesce(p_reason,'')),''),v_actor
  );

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    v_actor,v_actor_name,'voucher_allocation_revoked','voucher_allocation',p_allocation_id::text,v_allocation.partner_id,
    jsonb_build_object('quantity_revoked',p_quantity,'remaining_unissued',v_remaining-p_quantity),
    jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),''))
  );

  return jsonb_build_object(
    'success',true,
    'allocation_id',p_allocation_id,
    'revoked_unissued',p_quantity,
    'remaining_unissued',v_remaining-p_quantity
  );
end;
$$;

revoke all on function public.admin_engine_revoke_unissued(uuid,integer,text,uuid) from public, anon;
grant execute on function public.admin_engine_revoke_unissued(uuid,integer,text,uuid) to authenticated, service_role;

create or replace function public.admin_engine_retire_version(
  p_version_id uuid,
  p_reason text default null,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_actor_name text;
  v_status text;
  v_closed bigint;
begin
  if p_version_id is null then raise exception 'Version is required'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
  into v_actor_name
  from public.admin_users a
  where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  -- Same Version serialization domain as issuance migration 026 and allocation above.
  perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));

  select vv.status into v_status
  from public.voucher_versions vv
  where vv.id=p_version_id
  for update;
  if not found then raise exception 'Voucher Version not found'; end if;
  if v_status<>'active' then raise exception 'Only active Voucher Versions can be retired'; end if;

  update public.voucher_versions set status='inactive' where id=p_version_id;

  update public.partner_voucher_allocations
  set status='closed',updated_at=now()
  where version_id=p_version_id and status='active';
  get diagnostics v_closed=row_count;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,after_data,metadata
  ) values (
    v_actor,v_actor_name,'voucher_version_retired','voucher_version',p_version_id::text,
    jsonb_build_object('status','inactive','allocations_closed',v_closed),
    jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),''))
  );

  return jsonb_build_object(
    'success',true,
    'version_id',p_version_id,
    'status','inactive',
    'allocations_closed',v_closed
  );
end;
$$;

revoke all on function public.admin_engine_retire_version(uuid,text,uuid) from public, anon;
grant execute on function public.admin_engine_retire_version(uuid,text,uuid) to authenticated, service_role;
