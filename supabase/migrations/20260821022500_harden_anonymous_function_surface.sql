-- Harden anonymous function surface.
-- Only the explicit customer-facing RPC get_public_voucher(uuid) should remain
-- directly executable by anon. Internal trigger/helper functions must not be
-- exposed as callable RPC endpoints.

revoke execute on function public.assign_partner_code_before_insert() from public, anon;
revoke execute on function public.filter_voucher_branch_by_allocation_scope() from public, anon;
revoke execute on function public.guard_allocation_supply_capacity() from public, anon;
revoke execute on function public.guard_partner_global_voucher_quota() from public, anon;
revoke execute on function public.guard_voucher_branch_snapshot_flag() from public, anon;
revoke execute on function public.guard_voucher_branch_snapshot_rows() from public, anon;
revoke execute on function public.guard_voucher_delivery_snapshot_immutable() from public, anon;
revoke execute on function public.normalize_customer_phone(text) from public, anon;
revoke execute on function public.snapshot_voucher_delivery_policy() from public, anon;

-- Preserve the intended public customer voucher lookup contract explicitly.
grant execute on function public.get_public_voucher(uuid) to anon;
