# Evolution Voucher Admin Portal Backend Contract v1

Status: reconstruction staging only. This contract is for the new Voucher backend and must not be used to mutate legacy production directly.

## Principle
Admin may operate across Partner tenants, but browser code must not directly mutate business tables. All Admin mutations must pass through an authenticated RPC or an Admin-verified Edge Function. Read-only Admin queries use scoped RPC/read models where the browser requires cross-tenant operational data.

## Canonical Admin mutation map

| Admin action | Canonical backend boundary | Notes |
|---|---|---|
| Create Partner | Edge Function `create-partner` -> `admin_provision_partner(...)` | Edge verifies the original Admin caller, creates Auth user, then calls the service-role-only atomic provisioning RPC |
| Set Partner status | RPC `admin_set_partner_status(uuid,text)` | Replaces direct `partners.update(...)`; synchronizes live Partner user status and writes audit log |
| Set Partner voucher limit | RPC `admin_set_partner_voucher_limit(uuid,integer)` | Uses canonical `count(vouchers)` rather than `partners.vouchers_issued`; zero means unlimited |
| Set Partner staff limit | RPC `admin_set_partner_staff_limit(uuid,integer)` or Admin wrapper Edge Function | Cannot be below existing non-removed Partner Staff count |
| Read Partner claim access | RPC `admin_get_partner_claim_access(uuid)` | Read-only scoped Admin operation |
| Set Partner claim access | RPC `admin_set_partner_claim_access(uuid,boolean,text[])` | Replaces browser writes to claim settings/claim branches |
| Reset Partner password | Edge Function `reset-partner-password` -> `admin_record_partner_password_reset(...)` | Auth Admin operation only; service_role remains server-only and password material is never logged |
| Create Evolution Staff | Edge Function `create-staff` -> `admin_provision_staff(...)` | Admin path uses atomic server provisioning; manager behavior remains separately authorization-scoped |
| Voucher Engine allocate/revoke/retire | Admin-verified `voucher-engine` Edge Function -> 033 RPCs | Business allocation events remain append-audited |
| Reverse Redemption | RPC `reverse_redemption(...)` | Admin only; preserves history |

## Current reconstructed frontend state
The reconstructed `admin.html` no longer performs direct browser INSERT/UPDATE/DELETE against business tables for Partner controls. Current Partner status, voucher-limit, staff-limit and claim-access controls use the canonical Admin RPCs. Admin directory and reporting data are loaded through Admin read RPCs rather than reopening broad browser table access.

Auth-management Edge Functions now have runtime proof outside the browser: create Partner, create Evolution Staff, Partner Staff lifecycle, Partner password reset and Voucher Engine Admin actions are exercised in local signed-JWT/Edge E2E tests. Whether a specific auth-management action is exposed as a UI control is a product-surface decision and must not be confused with backend authorization readiness.

## Read boundary
Admin is the sole cross-Partner operational realm. Browser-visible Admin data should be obtained from scoped Admin RPC/read models (`admin_dashboard_summary`, reports, `admin_partner_directory`, `admin_active_branches`, claim-access RPCs). Partner and Staff accounts must not inherit this visibility.

## Trusted server boundary
A service-role Supabase client is transport authority, not human authorization. Every Admin Edge Function must authorize the original signed caller first. Service-role credentials are reserved for trusted Auth admin operations and narrowly granted server RPCs; they are not a license for broad business-table DML. Browser code must never contain service_role credentials.

## Cutover gate
The Admin frontend/backend contract is acceptable only when:

1. No business-table INSERT/UPDATE/DELETE remains in browser Admin code.
2. Partner status, voucher-limit, staff-limit and claim-access controls call canonical Admin RPCs.
3. Auth-management actions, when exposed in UI, use their named Edge Functions rather than browser Auth-admin emulation.
4. Voucher Engine mutations use the Admin-verified Edge boundary and atomic database RPCs.
5. Admin mutation, security, signed-JWT, Edge and browser portal tests pass on the verified target/runtime path.
6. Audit log entries are produced for status, quota, claim-access, allocation, provisioning, password reset and reversal mutations as applicable.
7. Backend config remains fail-closed until the exact new target project is verified and all deployment gates pass.
