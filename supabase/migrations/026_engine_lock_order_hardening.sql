-- Voucher Engine lock-order hardening v1
-- Replace Version row locking at the insert trigger with a transaction advisory
-- lock. This preserves race-safe supply enforcement while avoiding a lock-order
-- cycle with flows that may already hold an Allocation row lock.

create or replace function public.guard_engine_issuance_capacity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_version_status text;
  v_supply_limit integer;
  v_version_issued bigint;
  v_allocated integer;
  v_revoked integer;
  v_allocation_issued bigint;
begin
  if new.version_id is null then
    return new;
  end if;

  -- Serialize issuance attempts for the same Version without taking a Version
  -- row lock. This avoids Version -> Allocation / Allocation -> Version deadlock
  -- cycles while still making supply_limit race-safe.
  perform pg_advisory_xact_lock(hashtextextended(new.version_id::text, 2601));

  select vv.status,vv.supply_limit
  into v_version_status,v_supply_limit
  from public.voucher_versions vv
  where vv.id=new.version_id;

  if not found then
    raise exception 'Voucher Version does not exist';
  end if;

  -- Re-check status at the actual insert boundary so a Version retired after
  -- the Partner RPC first read it cannot still issue a new Voucher.
  if v_version_status <> 'active' then
    raise exception 'Voucher Version is not active';
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
    -- Allocation is the second and final lock domain for issuance. The canonical
    -- order inside this trigger is Version advisory lock -> Allocation row lock.
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

-- Keep the existing trigger name; replacing the function updates its behavior.
comment on function public.guard_engine_issuance_capacity() is
'Canonical issuance capacity guard: Version advisory lock first, then Allocation row lock; rechecks Version active status at insert boundary.';
