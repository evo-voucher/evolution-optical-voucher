-- Restrict orphaned legacy test RPC from normal signed-in users.
--
-- Context:
--   * delete_my_test_voucher(text) has no current GitHub runtime callers.
--   * Production dependency audit found no function/policy/view/trigger references.
--   * Keep the function for rollback/recovery, but remove it from the normal
--     authenticated application surface.
--
-- Rollback:
--   grant execute on function public.delete_my_test_voucher(text) to authenticated;

revoke execute on function public.delete_my_test_voucher(text) from authenticated;
