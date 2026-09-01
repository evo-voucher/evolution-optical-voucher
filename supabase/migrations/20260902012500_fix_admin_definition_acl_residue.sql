-- Remove residual service_role EXECUTE grants left on the three Admin RPCs
-- after their definitions were converged to Production. Production remains read-only.

REVOKE EXECUTE ON FUNCTION public.admin_redemption_report(uuid, integer) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_set_partner_staff_limit(uuid, integer) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.admin_set_partner_status(uuid, text) FROM service_role;
