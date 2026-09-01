-- Converge voucher-stage Admin RPC EXECUTE ACLs with current Production.
-- Definition-normalized hashes for all functions below already match Production;
-- only service_role EXECUTE differs. Production remains read-only.

REVOKE EXECUTE ON FUNCTION public.admin_archive_voucher_template(uuid, text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_create_voucher_template_theme(text, text, text, text, text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_dashboard_summary() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_get_partner_claim_access(uuid) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_latest_activity(integer) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_mark_notifications_read() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_next_partner_code(text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_notifications(integer) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_partner_directory() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_partner_issue_period_stats() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_partner_reporting_summary() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_preview_allocation_effective_branches(uuid, uuid, boolean, text[]) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_preview_partner_code(text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_publish_voucher_version(uuid, text, numeric, numeric, text, integer, integer, date, numeric, numeric, integer, boolean, text, integer, boolean, text[], text, jsonb, text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_record_partner_password_reset(uuid) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_set_partner_claim_access(uuid, boolean, text[]) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_set_partner_voucher_limit(uuid, integer) FROM service_role;
