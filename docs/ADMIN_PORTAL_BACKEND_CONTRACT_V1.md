# Evolution Voucher Admin Portal Backend Contract v1

Status: reconstruction staging only. This contract is for the new Voucher backend and must not be used to mutate legacy production directly.

## Principle
Admin may operate across Partner tenants, but browser code must not directly mutate business tables. All Admin mutations must pass through an authenticated RPC or an Admin-verified Edge Function. Read-only Admin queries may continue to use RLS-protected SELECTs where appropriate.

## Canonical Admin mutation map

| Admin action | Canonical backend boundary | Notes |
|---|---|---|
| Create Partner | Edge Function `create-partner` | Verifies Admin caller, creates Auth user + Partner + Partner Admin profile |
| Set Partner status | RPC `admin_set_partner_status(uuid,text)` | Replaces direct `partners.update(...)`; also synchronizes live Partner user status and writes audit log |
| Set Partner voucher limit | RPC `admin_set_partner_voucher_limit(uuid,integer)` | Uses canonical `count(vouchers)` rather than `partners.vouchers_issued` |
| Set Partner staff limit | RPC `admin_set_partner_staff_limit(uuid,integer)` or Admin wrapper Edge Function | Cannot be below existing non-removed Partner Staff count |
| Read Partner claim access | RPC `admin_get_partner_claim_access(uuid)` | Read-only scoped Admin operation |
| Set Partner claim access | RPC `admin_set_partner_claim_access(uuid,boolean,text[])` | Replaces browser writes to claim settings/claim branches |
| Reset Partner password | Edge Function `reset-partner-password` | Auth Admin operation only; service_role remains server-only |
| Create Evolution Staff | Edge Function `create-staff` | Admin or authorised manager path per function contract |
| Voucher Engine allocate/revoke/retire | Admin-verified Voucher Engine server boundary | Business allocation events remain append-audited |
| Reverse Redemption | RPC `reverse_redemption(...)` | Admin only; preserves history |

## Historical Admin frontend paths that must be removed before cutover
The current historical `admin.html` still contains direct browser writes for at least:

- `db.from("partners").update({status: ...})`
- `db.from("partner_users").update({status: ...})`
- `db.from("partners").update({voucher_limit: ...})`

These are incompatible with the reconstructed default-deny mutation model and must be replaced by the canonical RPCs above.

## Read boundary
Admin is the sole cross-Partner operational realm. Admin may read Partner/Voucher/Redemption/Allocation data globally under authenticated Admin RLS. Partner and Staff accounts must not inherit this visibility.

## Trusted server boundary
A service-role Supabase client is transport authority, not human authorization. Every Admin Edge Function must verify the original caller as an active Admin before using service_role for cross-Partner writes. Browser code must never contain service_role credentials.

## Cutover gate
The new Admin frontend is not considered backend-compatible until:

1. No business-table INSERT/UPDATE/DELETE remains in browser Admin code.
2. Partner status and voucher-limit controls call the canonical Admin RPCs.
3. Claim access uses `admin_get_partner_claim_access` / `admin_set_partner_claim_access`.
4. Auth-management actions use the named Edge Functions.
5. Admin mutation contract test passes on the verified new Supabase target.
6. Audit log entries are produced for status, quota, claim-access, allocation and reversal mutations.
