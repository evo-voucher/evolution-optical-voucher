-- Strict Partner Tenant Isolation v1
-- Goal: one Partner must never be able to read, mutate, redeem against,
-- allocate from, or manage another Partner's business data.
-- Admin remains the only cross-Partner operational role.

-- 1) One active Partner identity per Auth user.
-- Removed historical rows may remain for audit, but a live login cannot belong
-- to two Partners at the same time.
create unique index if not exists uq_partner_users_live_user
on public.partner_users(user_id)
where removed_at is null;

-- 2) Canonical tenant assertion helper for RPCs / triggers.
create or replace function public.assert_partner_tenant(p_partner_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.is_voucher_admin() then
    return;
  end if;

  if p_partner_id is null or p_partner_id is distinct from public.current_partner_id() then
    raise exception 'Cross-Partner access denied';
  end if;
end;
$$;
revoke all on function public.assert_partner_tenant(uuid) from public, anon;
grant execute on function public.assert_partner_tenant(uuid) to authenticated;

-- 3) Hard data-consistency guard.
-- Even service-role or future code cannot accidentally attach a Voucher to
-- another Partner's Allocation.
create or replace function public.guard_voucher_partner_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_allocation_partner uuid;
begin
  if new.partner_id is null then
    raise exception 'Voucher partner_id is required';
  end if;

  if new.allocation_id is not null then
    select a.partner_id into v_allocation_partner
    from public.partner_voucher_allocations a
    where a.id = new.allocation_id;

    if v_allocation_partner is null then
      raise exception 'Voucher allocation does not exist';
    end if;

    if v_allocation_partner is distinct from new.partner_id then
      raise exception 'Voucher allocation belongs to a different Partner';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists vouchers_guard_partner_consistency on public.vouchers;
create trigger vouchers_guard_partner_consistency
before insert or update of partner_id, allocation_id on public.vouchers
for each row execute function public.guard_voucher_partner_consistency();

-- 4) Redemption tenant consistency.
-- Redemption.partner_id must always be the same tenant as Voucher.partner_id.
create or replace function public.guard_redemption_partner_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_voucher_partner uuid;
begin
  select v.partner_id into v_voucher_partner
  from public.vouchers v
  where v.id = new.voucher_id;

  if v_voucher_partner is null then
    raise exception 'Voucher does not exist';
  end if;

  if new.partner_id is null then
    new.partner_id := v_voucher_partner;
  elsif new.partner_id is distinct from v_voucher_partner then
    raise exception 'Redemption Partner does not match Voucher Partner';
  end if;

  return new;
end;
$$;

drop trigger if exists redemptions_guard_partner_consistency on public.redemptions;
create trigger redemptions_guard_partner_consistency
before insert or update of partner_id, voucher_id on public.redemptions
for each row execute function public.guard_redemption_partner_consistency();

-- 5) Partner Voucher Access and Allocation must never point across tenant context.
-- Data model already carries partner_id directly; add lookup indexes for RLS/RPC isolation.
create index if not exists idx_partner_users_partner_live
  on public.partner_users(partner_id, user_id)
  where removed_at is null;
create index if not exists idx_vouchers_partner_status
  on public.vouchers(partner_id, status, issued_at desc);
create index if not exists idx_redemptions_partner_time
  on public.redemptions(partner_id, redeemed_at desc);
create index if not exists idx_partner_claim_branches_partner
  on public.partner_claim_branches(partner_id, branch_id);
create index if not exists idx_partner_allocations_partner
  on public.partner_voucher_allocations(partner_id, status, created_at desc);

-- 6) Replace Partner-facing RLS with strict tenant predicates.
-- Admin may cross tenants; Partner may only read its own tenant.
drop policy if exists partners_read_scope on public.partners;
create policy partners_read_scope
on public.partners for select to authenticated
using (public.is_voucher_admin() or id = public.current_partner_id());

drop policy if exists partner_users_read_scope on public.partner_users;
create policy partner_users_read_scope
on public.partner_users for select to authenticated
using (
  public.is_voucher_admin()
  or (
    partner_id = public.current_partner_id()
    and (
      user_id = (select auth.uid())
      or public.current_partner_role() = 'partner_admin'
    )
  )
);

drop policy if exists partner_claim_settings_read_scope on public.partner_claim_settings;
create policy partner_claim_settings_read_scope
on public.partner_claim_settings for select to authenticated
using (public.is_voucher_admin() or partner_id = public.current_partner_id());

drop policy if exists partner_claim_branches_read_scope on public.partner_claim_branches;
create policy partner_claim_branches_read_scope
on public.partner_claim_branches for select to authenticated
using (public.is_voucher_admin() or partner_id = public.current_partner_id());

drop policy if exists vouchers_read_scope on public.vouchers;
create policy vouchers_read_scope
on public.vouchers for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
  or exists (
    select 1
    from public.redemptions r
    where r.voucher_id = vouchers.id
      and r.staff_user_id = (select auth.uid())
  )
);

drop policy if exists redemptions_read_scope on public.redemptions;
create policy redemptions_read_scope
on public.redemptions for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
  or staff_user_id = (select auth.uid())
  or public.current_staff_role() = 'all_branch_manager'
);

drop policy if exists partner_voucher_access_read_scope on public.partner_voucher_access;
create policy partner_voucher_access_read_scope
on public.partner_voucher_access for select to authenticated
using (public.is_voucher_admin() or partner_id = public.current_partner_id());

drop policy if exists partner_voucher_allocations_read_scope on public.partner_voucher_allocations;
create policy partner_voucher_allocations_read_scope
on public.partner_voucher_allocations for select to authenticated
using (public.is_voucher_admin() or partner_id = public.current_partner_id());

drop policy if exists voucher_allocation_events_read_scope on public.voucher_allocation_events;
create policy voucher_allocation_events_read_scope
on public.voucher_allocation_events for select to authenticated
using (public.is_voucher_admin() or partner_id = public.current_partner_id());

-- 7) Business invariant declaration:
-- Shared catalog tables (voucher_templates / voucher_versions) may be visible to
-- authorised Partners because they are product definitions, NOT tenant data.
-- Tenant-owned data always carries partner_id and is isolated by the rules above.
