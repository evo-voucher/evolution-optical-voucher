# Evolution Voucher — Canonical System Contract v1

Status: DRAFT SOURCE OF TRUTH
Scope: Evolution Voucher only
Backend: Supabase project `xfivcfwexcxsyiylgryn`
Frontend: GitHub Pages repo `evo-voucher/evolution-optical-voucher`

## 1. Governing Rule

No patch-driven development.

A business capability must have one canonical execution path. When multiple versions or compatibility layers exist, reconcile to one contract and retire obsolete paths instead of adding another wrapper.

Required change flow:

Evidence -> Root Cause -> Canonical Contract -> Source of Truth -> Structural Correction -> Remove Obsolete Path -> Test -> Record

## 2. Canonical User-Facing Entrances

Keep as production entrances:
- `index.html`
- `admin.html`
- `voucher-engine.html`
- `admin-staff.html`
- `admin-partner-password.html`
- `partner.html`
- `staff.html`
- `voucher.html`

Legacy / preview / test / launch pages must not contain independent business logic. They must either be retired or redirect to one of the canonical entrances.

## 3. Identity Realms

Exactly three operational realms:
- `admin`
- `partner`
- `staff`

Realm ownership:
- Admin Portal: admin only
- Voucher Engine: admin only
- Partner Portal: partner only (`partner_admin` or `partner_staff`)
- Staff Portal: staff only

No portal should accept another realm as a convenience fallback.

## 4. Canonical Edge Functions

Keep one server-side function per trusted operation:
- `bootstrap-admin` — first Admin bootstrap only
- `create-partner` — Admin creates Partner Auth identity + tenant binding
- `create-staff` — Admin/authorized manager creates Evolution Staff identity
- `manage-partner-staff` — Partner Admin manages Partner Staff identities
- `reset-partner-password` — Admin resets Partner Admin password
- `voucher-engine` — trusted Admin Voucher Engine mutations that require service role
- `admin-set-partner-staff-limit` — retain only if the canonical Admin UI still needs this server boundary; otherwise retire after contract review

No duplicate `voucher-engine-admin` function.

## 5. Canonical Voucher Lifecycle

One lifecycle only:

Template -> Version -> Allocation -> Issue -> Public View / Share -> Verify -> Redeem -> Report / Optional Admin Reversal

### Template
Canonical RPC:
- `admin_create_voucher_template_theme`

### Version
Canonical publish RPC:
- `admin_publish_voucher_version`

There must be no public canonical `v2`, `v3`, theme-wrapper, or compatibility publish path.

### Allocation
Canonical server path:
- Browser invokes Edge Function `voucher-engine`
- `voucher-engine` invokes service-only RPC `admin_engine_allocate`

Allocation branch scope is part of the canonical allocation contract.

There must be no active canonical `admin_engine_allocate_v2`, `admin_engine_allocate_v3`, `allocate_all`, or duplicate allocation path.

### Partner Catalog
Canonical RPC:
- `partner_issuable_voucher_catalog`

It must represent the same inventory/quota truth enforced by issuance.

### Issue
Canonical RPC:
- `issue_engine_voucher`

Partner identity must be derived from Auth. Browser must never submit `partner_id` for issuance.

Legacy issuance paths such as `issue_partner_voucher` and single-voucher compatibility wrappers are not canonical.

### Public Voucher
Canonical RPC:
- `get_public_voucher(p_token)`

Only token-addressed public-safe fields may be returned.

### Partner Share
Canonical RPC:
- `get_partner_voucher_share(p_voucher_id)`

Must use the issued Voucher's branch snapshot as authoritative where present.

### Verify
Canonical RPC:
- `verify_voucher`

### Redeem
Canonical RPC:
- `redeem_voucher`

Voucher row locking, expiry, usage limit, branch snapshot and staff authorization are enforced server-side.

### Reversal
Canonical RPC:
- `reverse_redemption`

Admin only. Original redemption history remains preserved.

## 6. Canonical Branch Scope Model

Effective redemption scope at issuance is:

Partner Claim Scope ∩ Version Scope ∩ Allocation Scope

The issued Voucher stores an immutable branch snapshot in `voucher_branches` and marks `branch_scope_snapshotted=true`.

Verify, Redeem, Public View and Partner Share must all resolve from the same issued snapshot once it exists.

## 7. Canonical Quota / Inventory Model

There are three independent limits:
- Partner global `voucher_limit` (`0 = unlimited`)
- Voucher Version `supply_limit` (`NULL = unlimited`)
- Allocation lot remaining quantity

Partner catalog and issuance must use the same truth. UI display must never invent a separate quota model.

## 8. Canonical Reporting

Admin reporting:
- `admin_dashboard_summary`
- `admin_voucher_report`
- `admin_redemption_report`

Partner reporting:
- `partner_voucher_summary`
- `partner_recent_vouchers`

Staff reporting:
- `staff_today_summary`
- `staff_recent_redemptions`

Status precedence must be defined once in server-side reporting logic.

## 9. Trusted Service-Role Boundary

Only Edge Functions may use the Supabase service-role key.

Service-only RPCs include identity provisioning and trusted mutation helpers such as:
- `admin_provision_partner`
- `admin_provision_staff`
- Partner Staff provisioning/mutation helpers
- first-Admin bootstrap helpers
- `admin_engine_allocate`

Browser code must never contain or receive the service-role key.

## 10. Migration Chain Discipline

The active `supabase/migrations` directory is part of the canonical rebuild source of truth.

Rules:
- It must not contain migrations that target a retired hosted backend, factory-reset experiment, temporary superuser compatibility path, or obsolete recovery route.
- Historical evidence belongs in Git history, not in the active rebuild chain.
- Corrective logic discovered before release should be folded into the canonical rebuild migration that owns that invariant where safe and unambiguous.
- Do not create another numbered migration merely to preserve an error that has never shipped as the canonical production baseline.
- Hosted Supabase migration history may remain historical; the repository rebuild chain should converge to the final canonical state.

## 11. Legacy Retirement Rule

A legacy function/page may remain temporarily only for rollback while cutover is unverified.

After canonical UAT passes:
1. remove browser references to obsolete paths
2. revoke public/authenticated execution where no longer required
3. remove obsolete redirect/test/preview pages where safe
4. remove obsolete function variants from the final rebuild baseline
5. regenerate a clean baseline migration set instead of carrying endless corrective migrations forward

## 12. Rebuild Requirement

The final repository must be sufficient to recreate the canonical system from zero:
- schema
- RLS
- identity realm model
- RPCs
- triggers/invariants
- Edge Functions
- branch seed data
- frontend config and production entrances

Hosted Supabase state and GitHub source must not intentionally drift.

## 13. Release Gate

Do not merge cutover to production until all of these pass against the canonical backend:

Admin Login -> Create Partner -> Configure Partner Claim Scope -> Create Voucher Template -> Publish Version -> Allocate Stock -> Partner Login -> Issue Voucher -> Public Voucher/Share -> Create Evolution Staff -> Staff Login -> Verify -> QR/Manual Redeem -> Reports -> Duplicate Redeem Rejected -> Wrong Branch Rejected -> Expired/Revoked Rules Verified

Only after this gate passes may the system be marked production-ready.
