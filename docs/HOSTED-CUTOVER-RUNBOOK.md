# Evolution Optical Voucher — Canonical Cutover Runbook

Status: CUTOVER IN PROGRESS

This runbook is the authoritative release route for the reconstructed Evolution Voucher system.

## Approved topology

- Canonical Voucher backend: `xfivcfwexcxsyiylgryn`
- XiaoE AI Core project: `uuqiwyqxllqsuboogbxh`
- Frontend: `https://evo-voucher.github.io/evolution-optical-voucher/`
- Ownership: GitHub = frontend; Supabase = backend.

The approved route is **canonical reconstruction**. Evolution Voucher and XiaoE AI Core are separate runtime boundaries.

## Non-negotiable boundaries

- Never deploy Voucher runtime or migrations into XiaoE AI Core.
- Never expose `service_role`, `sb_secret_`, or any privileged secret in browser code, GitHub Pages, HTML, or JS.
- Never treat migration application, a queued CI job, or a successful page load alone as proof of cutover.
- Preserve business data and verify integrity before and after high-impact changes.
- Partner tenant identity and Staff branch scope must be enforced server-side.
- One canonical issuance engine is preferred; legacy operational entry points must not create a second production path.

## State machine

### PREPARED
Frontend is fail-closed or still points to the last known-good backend. The canonical backend can be inspected without exposing it to production users.

### CUTOVER IN PROGRESS
Release-candidate source may target the exact canonical backend:

- `environment = production`
- `projectId = xfivcfwexcxsyiylgryn`
- `supabaseUrl = https://xfivcfwexcxsyiylgryn.supabase.co`
- publishable key begins with `sb_publishable_`
- `siteBase = https://evo-voucher.github.io/evolution-optical-voucher/`

The public `main` branch is not switched until automated gates and controlled UAT are complete.

### VERIFIED
Declared only after automated contracts, public deployment, full end-to-end UAT, phone/browser checks, and post-UAT integrity checks pass against the canonical backend.

Current flags:

- `cutover_state = CUTOVER_IN_PROGRESS`
- `hosted_cutover_verified = false`

## Phase 1 — Backend proof

Verified so far:

1. Canonical schema and migration chain restored through first-Admin bootstrap.
2. First Admin Auth identity and Admin realm created successfully; bootstrap code consumed and disabled.
3. RLS enabled on business tables; direct anon business-table access is absent.
4. Authenticated direct table writes are absent; mutations use RPC/Edge boundaries.
5. Service provisioning RPCs are service-role only.
6. Partner/Staff/Engine Edge Functions validate authenticated caller context before privileged actions.
7. Current database integrity audit reports no orphan/cross-tenant broken records.
8. Verify/Redeem branch-snapshot semantics and Partner share branch scope are aligned.

## Phase 2 — Source hardening

Before production activation:

1. Align CI and preflight target with `xfivcfwexcxsyiylgryn`.
2. Persist all database hotfix migrations in GitHub.
3. Record QR scanner redemptions as `qr` and manual entries as `manual_code`.
4. Require exact `partner` realm in Partner Portal and exact `staff` realm in Staff Portal.
5. Retire/redirect legacy operational HTML pages that still target the previous Supabase backend.
6. Remove or revoke obsolete/test issuance RPC entry points after confirming no canonical frontend dependency.
7. Re-run security and integrity checks.

## Phase 3 — Controlled end-to-end UAT

The required production smoke chain is:

`Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`

UAT must additionally verify:

- Partner and Staff login realms;
- allocation/quota behavior;
- branch snapshot and wrong-branch rejection;
- expired/redeemed/revoked behavior;
- duplicate redemption protection;
- QR vs manual redemption method reporting;
- Partner/Staff/Admin history and report consistency;
- customer public Voucher rendering;
- actual WhatsApp share content;
- iPhone Safari/PWA and camera QR permission/scan.

## Phase 4 — Production activation

After all gates pass:

1. Record pre-cutover GitHub and Supabase state.
2. Switch public `main` backend configuration to `xfivcfwexcxsyiylgryn`.
3. Deploy GitHub Pages.
4. Run Production Public Smoke against the deployed site.
5. Repeat a non-destructive realm/public-page check.
6. Confirm no legacy operational entry point can still mutate the previous backend.
7. Recheck business counts/integrity and unexpected residue.
8. Only then set `cutover_state = VERIFIED` and `hosted_cutover_verified = true`.

## Rollback rule

If deployment or deployed verification fails:

1. Restore `assets/js/backend-config.js` to the last known-good or fail-closed configuration.
2. Preserve logs and evidence.
3. Diagnose the owning layer.
4. Fix repository source/migration/adapter, not production data by hand.
5. Re-run the failed gate and relevant regression suite.
6. Recheck database integrity and residue.

## Definition of done

The canonical reconstruction is complete only when all automated gates, full controlled UAT, public Pages smoke, phone/browser verification, and post-UAT integrity checks pass against `xfivcfwexcxsyiylgryn`.
