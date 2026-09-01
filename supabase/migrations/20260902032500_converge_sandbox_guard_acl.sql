-- Converge EXECUTE ACLs for sandbox-sensitive trigger helpers on voucher-stage.
-- Definitions intentionally remain canonical/strict on Stage: Production carries
-- temporary sandbox-reset bypass logic that should not be copied into dedicated Stage.
-- Production remains read-only.

REVOKE ALL ON FUNCTION public.guard_audit_log_immutable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guard_audit_log_immutable() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_audit_log_immutable() FROM service_role;

REVOKE ALL ON FUNCTION public.guard_redemption_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guard_redemption_history() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_redemption_history() FROM service_role;
