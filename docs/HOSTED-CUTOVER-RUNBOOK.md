# Evolution Optical Voucher — Hosted Cutover Runbook

Status: VERIFIED

This runbook is the authoritative production route for Evolution Voucher.

## Approved topology

- Production Voucher project: `hukihbcyyqhanaqrizvm`
- XiaoE AI Core project: `uuqiwyqxllqsuboogbxh`
- Frontend: `https://evo-voucher.github.io/evolution-optical-voucher/`

The earlier clean-third-project plan is retired. The approved route is **existing-production convergence** because the Free plan permits only two active projects. Production remains the live Voucher backend while compatibility boundaries preserve hosted semantics and canonical CI remains independently rebuildable.

## Non-negotiable boundaries

- Never deploy Voucher runtime into XiaoE AI Core.
- Never expose `service_role`, `sb_secret_`, or any privileged secret in browser code, GitHub Pages, HTML, or JS.
- Never treat migration application, a queued CI job, or a successful page load alone as proof of cutover.
- Preserve live production data and verify counts before and after high-impact changes.
- Hosted compatibility drift is allowed only when intentional, documented, and bounded by the environment adapter.
- Do not overwrite hosted semantics merely to make production source text match canonical source text.

## State machine

### PREPARED
Frontend is fail-closed. Project ID, Supabase URL, and publishable key remain blank.

### CUTOVER IN PROGRESS
Frontend may be enabled only with the exact approved production target:

- `environment = production`
- `projectId = hukihbcyyqhanaqrizvm`
- `supabaseUrl = https://hukihbcyyqhanaqrizvm.supabase.co`
- publishable key begins with `sb_publishable_`
- `siteBase = https://evo-voucher.github.io/evolution-optical-voucher/`

XiaoE AI Core and secret/service-role material remain forbidden.

### VERIFIED
Declared after CI, Pages, deployed browser smoke, QR Scan/branch-aware Verify, and post-smoke production baseline all passed on 2026-08-16.

Current flags:

- `cutover_state = VERIFIED`
- `hosted_cutover_verified = true`

## Phase 1 — Production compatibility proof

Completed evidence:

1. Canonical CI green.
2. Production Admin / Partner / Staff Auth-context reads passed.
3. Real Staff Voucher verify succeeded without unintended writes.
4. Edge Function drift was classified as either identical or intentional hosted compatibility.
5. Security hardening preserved the business baseline.
6. Recovery / rollback path is explicit.

Verified baseline before and after frontend cutover: 43 Vouchers / 8 Redemptions.

## Phase 2 — Frontend activation

The production frontend uses only the browser-safe modern Supabase publishable key. No service-role credential is present in browser configuration.

Activation and later QR-scanner commits triggered and passed the relevant production checks, including Hosted Cutover Preflight, Free Supabase Runtime Smoke, GitHub Pages deployment, Public Smoke, and backup/recovery workflow.

## Phase 3 — Deployed verification

Completed against the public production site:

1. Main launcher and deployed Pages surface load.
2. Admin login resolves to Admin realm and authoritative dashboard data.
3. Partner login resolves to the correct tenant and Partner summary.
4. Staff login resolves to the correct branch/role context.
5. Staff can verify a real valid Voucher at an allowed branch.
6. Staff QR Scan parses a real Voucher and still enforces branch restrictions.
7. Public Voucher page renders production Voucher details and Redeemable Branches.
8. Production browser configuration contains only the publishable credential class.
9. Production counts remained 43 Vouchers / 8 Redemptions because browser smoke did not redeem or otherwise mutate business data.
10. Historical `TEST-MINES-001` data was confirmed to predate this cutover and is not current smoke residue.

## Production smoke chain

For any later controlled write smoke, the full chain remains:

`Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`

Write smoke must have a cleanup/recovery plan and must not be confused with read-only verification.

## Rollback rule

If a later deployment or deployed browser verification fails:

1. Restore `assets/js/backend-config.js` to fail-closed first if the failure can expose users to a broken path.
2. Preserve logs and evidence.
3. Diagnose the owning layer.
4. Fix repository source / migration / adapter, not production data by hand.
5. Re-run the failed gate and full relevant regression.
6. Recheck production baseline and residue.

## Definition of done

The production frontend lineage has now satisfied:

- production-mode Preflight green;
- full Runtime Smoke green;
- Pages deployment green;
- Public Smoke green;
- deployed Admin / Partner / Staff / Public Voucher browser verification green;
- Staff QR Scan and allowed-branch Verify green;
- production baseline/recovery check green.

Therefore:

`hosted_cutover_verified = true`
