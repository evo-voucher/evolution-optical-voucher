-- Harden anonymous function surface.
-- Only the explicit customer-facing RPC get_public_voucher(uuid) should remain
-- directly executable by anon. Internal trigger/helper functions must not be
-- exposed as callable RPC endpoints.
--
-- Fresh canonical rebuilds may reach this historical hardening step before
-- some helper functions are introduced. In that case there is nothing to
-- revoke yet, so each revoke is intentionally guarded.

do $migration$
begin
  if to_regprocedure('public.assign_partner_code_before_insert()') is not null then
    revoke execute on function public.assign_partner_code_before_insert() from public, anon;
  end if;

  if to_regprocedure('public.filter_voucher_branch_by_allocation_scope()') is not null then
    revoke execute on function public.filter_voucher_branch_by_allocation_scope() from public, anon;
  end if;

  if to_regprocedure('public.guard_allocation_supply_capacity()') is not null then
    revoke execute on function public.guard_allocation_supply_capacity() from public, anon;
  end if;

  if to_regprocedure('public.guard_partner_global_voucher_quota()') is not null then
    revoke execute on function public.guard_partner_global_voucher_quota() from public, anon;
  end if;

  if to_regprocedure('public.guard_voucher_branch_snapshot_flag()') is not null then
    revoke execute on function public.guard_voucher_branch_snapshot_flag() from public, anon;
  end if;

  if to_regprocedure('public.guard_voucher_branch_snapshot_rows()') is not null then
    revoke execute on function public.guard_voucher_branch_snapshot_rows() from public, anon;
  end if;

  if to_regprocedure('public.guard_voucher_delivery_snapshot_immutable()') is not null then
    revoke execute on function public.guard_voucher_delivery_snapshot_immutable() from public, anon;
  end if;

  if to_regprocedure('public.normalize_customer_phone(text)') is not null then
    revoke execute on function public.normalize_customer_phone(text) from public, anon;
  end if;

  if to_regprocedure('public.snapshot_voucher_delivery_policy()') is not null then
    revoke execute on function public.snapshot_voucher_delivery_policy() from public, anon;
  end if;
end
$migration$;

-- Preserve the intended public customer voucher lookup contract explicitly.
grant execute on function public.get_public_voucher(uuid) to anon;
