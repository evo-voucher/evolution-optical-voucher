-- Align fresh rebuild anonymous RPC privileges with the hardened production boundary.
-- The only intentionally anonymous SECURITY DEFINER RPC is get_public_voucher(uuid).

revoke execute on function public.admin_partner_reporting_summary() from public, anon;
revoke execute on function public.admin_purge_expired_unredeemed_vouchers(uuid) from public, anon;
revoke execute on function public.admin_voucher_type_summary(uuid) from public, anon;
revoke execute on function public.attach_voucher_customer() from public, anon;

-- Preserve the intended customer-facing anonymous lookup explicitly.
grant execute on function public.get_public_voucher(uuid) to anon;
