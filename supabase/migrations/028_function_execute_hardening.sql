-- Function EXECUTE hardening v1
-- PostgreSQL grants EXECUTE on newly created functions to PUBLIC by default.
-- For this system, RPC exposure must be explicit. Trigger/internal functions should
-- not appear callable to anon merely because of PostgreSQL defaults.

-- Remove inherited PUBLIC/anon execution from every currently defined public function.
-- Existing explicit grants to authenticated/service_role are intentionally preserved.
revoke execute on all functions in schema public from public, anon;

-- Future functions created by the migration owner must also start default-deny.
alter default privileges in schema public
  revoke execute on functions from public;

-- Explicit anonymous API allow-list.
-- This is the only customer-facing unauthenticated RPC.
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;

-- Canonical identity/authorization helpers used by authenticated RPCs/frontends.
-- These grants are explicit even if earlier migrations already granted them.
grant execute on function public.is_voucher_admin() to authenticated;
grant execute on function public.current_partner_id() to authenticated;
grant execute on function public.current_partner_role() to authenticated;
grant execute on function public.current_staff_branch_id() to authenticated;
grant execute on function public.current_staff_role() to authenticated;
grant execute on function public.current_operational_realm() to authenticated;
grant execute on function public.assert_partner_tenant(uuid) to authenticated, service_role;
grant execute on function public.is_trusted_service_role() to authenticated, service_role;

comment on schema public is
'Evolution Voucher API schema. Function EXECUTE is default-deny; browser/anon RPC exposure must be explicitly granted by migration.';
