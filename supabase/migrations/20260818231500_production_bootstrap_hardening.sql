-- Production launch hardening.
-- Keep the partner voucher share RPC deterministic and close the consumed
-- first-admin bootstrap status endpoint to browser roles.

alter function public.get_partner_voucher_share(uuid)
  set search_path = public;

revoke execute on function public.admin_bootstrap_status()
  from anon, authenticated;
