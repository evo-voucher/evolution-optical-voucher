-- Strict Partner isolation write guards v1
-- Extends tenant isolation beyond SELECT/RLS into all partner-owned write paths.

create or replace function public.guard_partner_claim_setting_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.assert_partner_tenant(new.partner_id);
  return new;
end;
$$;

drop trigger if exists partner_claim_settings_tenant_guard on public.partner_claim_settings;
create trigger partner_claim_settings_tenant_guard
before insert or update of partner_id on public.partner_claim_settings
for each row execute function public.guard_partner_claim_setting_tenant();

create or replace function public.guard_partner_claim_branch_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.assert_partner_tenant(new.partner_id);
  return new;
end;
$$;

drop trigger if exists partner_claim_branches_tenant_guard on public.partner_claim_branches;
create trigger partner_claim_branches_tenant_guard
before insert or update of partner_id on public.partner_claim_branches
for each row execute function public.guard_partner_claim_branch_tenant();

create or replace function public.guard_partner_voucher_access_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.assert_partner_tenant(new.partner_id);
  return new;
end;
$$;

drop trigger if exists partner_voucher_access_tenant_guard on public.partner_voucher_access;
create trigger partner_voucher_access_tenant_guard
before insert or update of partner_id on public.partner_voucher_access
for each row execute function public.guard_partner_voucher_access_tenant();

create or replace function public.guard_partner_allocation_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.assert_partner_tenant(new.partner_id);
  return new;
end;
$$;

drop trigger if exists partner_voucher_allocations_tenant_guard on public.partner_voucher_allocations;
create trigger partner_voucher_allocations_tenant_guard
before insert or update of partner_id on public.partner_voucher_allocations
for each row execute function public.guard_partner_allocation_tenant();

create or replace function public.guard_allocation_event_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_allocation_partner uuid;
  v_allocation_version uuid;
begin
  select a.partner_id, a.version_id
  into v_allocation_partner, v_allocation_version
  from public.partner_voucher_allocations a
  where a.id=new.allocation_id;

  if v_allocation_partner is null then
    raise exception 'Allocation does not exist';
  end if;

  if new.partner_id is distinct from v_allocation_partner then
    raise exception 'Allocation event Partner mismatch';
  end if;

  if new.version_id is distinct from v_allocation_version then
    raise exception 'Allocation event Version mismatch';
  end if;

  perform public.assert_partner_tenant(new.partner_id);
  return new;
end;
$$;

drop trigger if exists voucher_allocation_events_tenant_guard on public.voucher_allocation_events;
create trigger voucher_allocation_events_tenant_guard
before insert or update of allocation_id, partner_id, version_id on public.voucher_allocation_events
for each row execute function public.guard_allocation_event_tenant();

-- Partner users may only be created/changed inside the same Partner tenant unless Admin.
create or replace function public.guard_partner_user_tenant()
returns trigger
language plpgsql
set search_path = public
as $$;
begin
  if public.is_voucher_admin() then
    return new;
  end if;

  if new.partner_id is null or new.partner_id is distinct from public.current_partner_id() then
    raise exception 'Cross-Partner Partner User write denied';
  end if;

  return new;
end;
$$;

drop trigger if exists partner_users_tenant_guard on public.partner_users;
create trigger partner_users_tenant_guard
before insert or update of partner_id on public.partner_users
for each row execute function public.guard_partner_user_tenant();

-- Ensure voucher branch mapping itself cannot bridge tenants indirectly.
create or replace function public.guard_voucher_branch_mapping()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_partner uuid;
begin
  select v.partner_id into v_partner
  from public.vouchers v
  where v.id=new.voucher_id;

  if v_partner is null then
    raise exception 'Voucher does not exist';
  end if;

  perform public.assert_partner_tenant(v_partner);
  return new;
end;
$$;

drop trigger if exists voucher_branches_tenant_guard on public.voucher_branches;
create trigger voucher_branches_tenant_guard
before insert or update of voucher_id on public.voucher_branches
for each row execute function public.guard_voucher_branch_mapping();

-- NOTE: Admin is intentionally exempt because Admin is the only cross-Partner operator.
-- Service-role code must still pass data-consistency triggers defined in 018.
