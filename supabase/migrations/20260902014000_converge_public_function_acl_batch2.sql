-- Converge voucher-stage public function EXECUTE ACLs with current Production
-- for functions whose normalized definitions already match exactly.
-- Production remains read-only.

REVOKE EXECUTE ON FUNCTION public._cleanup_stale_voucher_data(integer, uuid, text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_voucher_report(uuid, integer) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_voucher_type_summary(uuid) FROM service_role;

REVOKE EXECUTE ON FUNCTION public.current_partner_id() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.current_partner_role() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.current_staff_branch_id() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.current_staff_role() FROM service_role;

REVOKE EXECUTE ON FUNCTION public.filter_voucher_branch_by_allocation_scope() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.filter_voucher_branch_by_allocation_scope() FROM service_role;

REVOKE EXECUTE ON FUNCTION public.get_public_voucher(uuid) FROM service_role;

REVOKE EXECUTE ON FUNCTION public.guard_admin_identity_realm() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_admin_identity_realm() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_allocation_event_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_allocation_event_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_engine_issuance_capacity() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_engine_issuance_capacity() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_allocation_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_allocation_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_claim_branch_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_claim_branch_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_claim_setting_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_claim_setting_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_identity_realm() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_identity_realm() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_user_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_user_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_partner_voucher_access_tenant() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_voucher_access_tenant() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_published_voucher_version() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_published_voucher_version() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_redemption_partner_consistency() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_redemption_partner_consistency() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_staff_identity_realm() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_staff_identity_realm() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_mapping() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_mapping() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_snapshot_flag() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_snapshot_flag() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_snapshot_rows() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_branch_snapshot_rows() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_delivery_snapshot_immutable() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_delivery_snapshot_immutable() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_partner_consistency() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_partner_consistency() FROM service_role;

REVOKE EXECUTE ON FUNCTION public.is_voucher_admin() FROM service_role;
REVOKE EXECUTE ON FUNCTION public.partner_set_staff_access(boolean) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.reverse_redemption(uuid, text) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.touch_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_updated_at() FROM service_role;
