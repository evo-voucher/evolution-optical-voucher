# Evolution Optical Voucher — Hosted Cutover Runbook

Status: CUTOVER IN PROGRESS

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
- `hosted_cutover_verified` remains false until deployed browser verification closes.

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
May be declared only after CI, Pages, deployed browser smoke, and post-smoke production baseline all pass.

## Phase 1 — Production compatibility proof

Required evidence:

1. Latest canonical CI fully green.
2. Production Admin / Partner / Staff Auth-context reads pass.
3. Real Staff Voucher verify succeeds without unintended writes.
4. Edge Function drift is classified as either identical or intentional hosted compatibility.
5. Security hardening does not change business baseline.
6. Recovery / rollback path is explicit.

Current verified baseline before frontend cutover: 43 Vouchers / 8 Redemptions.

## Phase 2 — Frontend activation

Enable only the browser-safe production configuration. Use the modern Supabase publishable key. Never use service-role credentials.

Activation commit must trigger:

- Hosted Cutover Preflight
- Free Supabase Runtime Smoke
- GitHub Pages deployment
- backup/recovery workflow where configured

## Phase 3 — Deployed verification

After Pages deploys, verify against the public site:

1. Main launcher loads.
2. Admin page shows Sign In; First-Time Setup remains unavailable when bootstrap is closed.
3. Admin login resolves to Admin realm.
4. Partner login resolves to the correct tenant and dashboard.
5. Staff login resolves to the correct branch/role context.
6. Staff can verify a real valid Voucher at an allowed branch.
7. Public Voucher page loads the frozen issued snapshot.
8. Voucher Engine / Admin navigation loads correctly.
9. No browser request contains service-role credentials.
10. Production business counts remain unchanged unless a deliberate smoke mutation was made and fully cleaned up.

## Production smoke chain

For any later controlled write smoke, the full chain remains:

`Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`

Write smoke must have a cleanup/recovery plan and must not be confused with read-only verification.

## Rollback rule

If Preflight, Runtime Smoke, Pages deployment, or deployed browser verification fails after activation:

1. Restore `assets/js/backend-config.js` to fail-closed first if the failure can expose users to a broken path.
2. Preserve logs and evidence.
3. Diagnose the owning layer.
4. Fix repository source / migration / adapter, not production data by hand.
5. Re-run the failed gate and full relevant regression.
6. Recheck production baseline and residue.

## Definition of done

Set `hosted_cutover_verified = true` only when the same production frontend lineage has:

- production-mode Preflight green;
- full Runtime Smoke green;
- Pages deployment green;
- deployed Admin / Partner / Staff / Public Voucher browser verification green;
- production baseline/recovery check green.

Until then:

`hosted_cutover_verified = false`
