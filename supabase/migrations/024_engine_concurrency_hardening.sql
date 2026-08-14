-- Voucher Engine concurrency hardening v1
-- Enforce Version supply and Allocation quota at the database insert boundary.
-- This protects every issuance path, including future code that may bypass the
-- current Partner RPC. Locks serialize competing issuance for the same Version
-- and Allocation before counts are evaluated.

create or replace function public.guard_engine_issuance_capacity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_supply_limit integer;
  v_version_issued bigint;
  v_allocated integer;
  v_revoked integer;
  v_allocation_issued bigint;
begin
  if new.version_id is null then
    return new;
  end if;

  -- One row lock per Version makes the global supply check race-safe.
  select vv.supply_limit
  into v_supply_limit
  from public.voucher_versions vv
  where vv.id=new.version_id
  for update;

  if not found then
    raise exception 'Voucher Version does not exist';
  end if;

  if v_supply_limit is not null then
    select count(*) into v_version_issued
    from public.vouchers v
    where v.version_id=new.version_id;

    if v_version_issued >= v_supply_limit then
      raise exception 'Voucher Version supply limit reached';
    end if;
  end if;

  if new.allocation_id is not null then
    -- Lock the Allocation before checking remaining unissued quantity.
    select a.quantity_allocated,a.quantity_revoked
    into v_allocated,v_revoked
    from public.partner_voucher_allocations a
    where a.id=new.allocation_id
      and a.partner_id=new.partner_id
      and a.version_id=new.version_id
      and a.status='active'
      and (a.valid_from is null or a.valid_from<=now())
      and (a.valid_until is null or a.valid_until>=now())
    for update;

    if not found then
      raise exception 'Active Voucher Allocation not found for this Partner and Version';
    end if;

    select count(*) into v_allocation_issued
    from public.vouchers v
    where v.allocation_id=new.allocation_id;

    if v_allocation_issued >= (v_allocated-v_revoked) then
      raise exception 'Voucher Allocation limit reached';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists vouchers_guard_engine_capacity on public.vouchers;
create trigger vouchers_guard_engine_capacity
before insert on public.vouchers
for each row execute function public.guard_engine_issuance_capacity();

-- Partner dashboard counters should use Voucher rows as authoritative issuance
-- truth instead of depending on a transitional cached partners.vouchers_issued value.
create or replace function public.get_my_partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,
    'partner_code',p.partner_code,
    'partner_name',p.partner_name,
    'voucher_limit',p.voucher_limit,
    'vouchers_issued',(select count(*) from public.vouchers v where v.partner_id=p.id),
    'remaining',greatest(0,p.voucher_limit-(select count(*) from public.vouchers v where v.partner_id=p.id)),
    'partner_status',p.status,
    'role',pu.role,
    'staff_name',pu.staff_name,
    'staff_access_enabled',p.staff_access_enabled,
    'staff_limit',p.staff_limit,
    'can_issue_voucher',case
      when pu.role='partner_admin' then true
      when pu.role='partner_staff' then p.staff_access_enabled
      else false
    end
  ) into v_result
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if v_result is null then
    raise exception 'Active Partner account not found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_my_partner_dashboard() from public, anon;
grant execute on function public.get_my_partner_dashboard() to authenticated;
