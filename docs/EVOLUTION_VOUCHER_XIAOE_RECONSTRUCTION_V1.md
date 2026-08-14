# Evolution Voucher — XiaoE Historical Reconstruction v1

Status: BACKEND RECONSTRUCTION BASELINE
Date: 2026-08-15
Repository: evo-voucher/evolution-optical-voucher

## 1. Reconstruction method

This project is not rebuilt by copying the latest UI or blindly cloning the legacy Supabase schema.

XiaoE evidence priority:
1. Current verified state
2. Verified successful production behavior
3. Historical decisions and failure lessons
4. Old implementation details

Working loop:
Observe → Decide → Execute → Verify → Learn → Persist → Review.

Core motto:
- Root before flower
- Trace the data, not the symptom
- Minimum correct structural change

## 2. What history proved should remain

### Business spine
Admin → Partner → Partner Staff → Voucher → Branch → Redemption → Record

This is the stable commercial transaction path and remains the system spine.

### Distinct operating surfaces
- Admin Portal
- Partner Portal
- Staff Portal
- Public Voucher page

The UI can evolve independently, but these identities and responsibilities must remain distinct.

### Partner rules
- Admin creates and controls Partners.
- Partner can be active, suspended or archived.
- Suspended Partner cannot issue vouchers.
- Partner Admin may enable or disable Partner Staff issuance.
- Partner Staff accounts have a configurable limit.
- Removing Staff keeps historical voucher/redemption attribution.

### Branch rules
- Admin controls Partner claim scope.
- Partner may be all-branches or selected-branches.
- Voucher Version may also be all-branches or selected-branches.
- Final redeem scope is the safe intersection of Partner scope and Voucher Version scope.

### Voucher rules
- Voucher code is unique.
- Public token is separate from voucher code and internal IDs.
- Customer IC/Passport is not collected.
- Customer public page exposes only minimum customer-facing information.
- Voucher Type defines behavior.
- Theme defines presentation.
- Voucher Type and Theme must never be hard-wired together.

### Redemption rules
- Verification is read-only.
- Redemption is a database transaction boundary.
- Voucher row is locked during redemption.
- Expired, revoked, exhausted or branch-invalid vouchers cannot redeem.
- usage_count/usage_limit is the canonical usage model.
- Concurrent scans serialize on the voucher row.
- Redemption history is never deleted.
- Reversal is an explicit audited state transition.

## 3. What history proved should be retired

- UI button visibility as a security boundary.
- Direct browser writes for sensitive mutations.
- Partner/Admin/Staff identity mixed in one role column.
- `customer_ic` collection.
- Repeated permissive RLS policies for the same table/action.
- Publicly callable SECURITY DEFINER functions without deliberate authorization design.
- Patching RM60 and multi-voucher logic as two unrelated systems.
- Treating AI/XiaoE as a dependency of the voucher transaction path.
- Mixing CRM, AI memory, voucher transactions and platform health tables into one undifferentiated core.

## 4. New architecture

### Layer A — Stable Core
- admin_users
- partners
- partner_users
- staff_users
- branches
- partner_claim_settings
- partner_claim_branches
- vouchers
- voucher_branches
- redemptions
- admin_audit_log

### Layer B — Voucher Engine
- voucher_templates
- voucher_versions
- voucher_version_branches
- voucher_rules
- partner_voucher_access
- partner_voucher_allocations
- voucher_allocation_events

### Layer C — Application / UI
- Admin
- Partner
- Staff
- Public Voucher
- PWA / install wrappers

### Layer D — XiaoE intelligence
XiaoE may read, analyze, explain and assist, but must not be required for Issue / Verify / Redeem transactions.
If AI is unavailable, voucher operations must continue normally.

## 5. Canonical mutation boundaries

RPCs:
- issue_partner_voucher
- issue_engine_voucher
- verify_voucher
- redeem_voucher
- reverse_redemption
- get_public_voucher
- get_my_partner_dashboard
- get_my_partner_claim_access
- partner_set_staff_access
- admin_set_partner_claim_access

Compatibility RPCs preserve the current Partner UI while routing into the canonical engine:
- create_partner_voucher_controlled
- create_partner_multi_voucher_controlled
- partner_staff_capacity

Edge Functions:
- create-partner
- create-staff
- manage-partner-staff

Service-role keys remain server-side only.

## 6. Security model

Default posture: deny direct mutation.

- RLS enabled immediately.
- Browser gets SELECT only where needed.
- Sensitive writes go through RPC/Edge Function authorization boundaries.
- Foreign keys use restrict/cascade deliberately.
- Audit history is append-only.
- Redemption history is immutable except controlled reversal.
- Voucher identity fields are immutable after issuance.
- Field-level integrity is protected by triggers, not only RLS.

## 7. Proven historical behaviors preserved

- Mobile-first Partner experience.
- QR generation and Staff scanning.
- WhatsApp/share flow.
- Branch name/address/phone on customer-facing voucher.
- Partner Staff on/off switch.
- Partner Staff account limit.
- All Branch Manager model for Evolution Staff administration.
- Template / Version / Allocation model.
- True calendar-month validity support.
- Allocation lock before issuance.
- Voucher lock before redemption.

## 8. Deployment rule

Legacy project `Evolution voucher projects` is a historical reference and current production source. It must not be used as a scratchpad for reconstruction.

The migrations in `supabase/migrations/` are targeted at a new blank Supabase project. They are not to be applied to the legacy production database as-is.

Deployment sequence:
1. Bind the new blank Supabase project.
2. Apply migrations in numeric order.
3. Seed Admin + Branch baseline.
4. Deploy Edge Functions with JWT verification enabled.
5. Run integrity/security tests.
6. Seed one test Partner + one test Staff.
7. Run Issue → Verify → Redeem → Report → Reverse test.
8. Update frontend to the new project URL/key only after backend verification.
9. Preserve legacy production until cutover passes rollback checks.

## 9. Current reconstruction baseline

Implemented in repository:
- 001 Core Schema
- 002 Identity + RLS
- 003 Core Issue RPC
- 004 Verify RPC
- 005 Atomic Redeem RPC
- 006 Public Voucher RPC
- 007 Reversal RPC
- 008 Partner controls
- 009 Voucher Engine Schema
- 010 Engine Issue RPC
- 011 Frontend compatibility RPCs
- 012 Integrity guards
- Edge Function: manage-partner-staff
- Edge Function: create-partner
- Edge Function: create-staff

This document is the architecture decision baseline for subsequent backend and frontend work.
