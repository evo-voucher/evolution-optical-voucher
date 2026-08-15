# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-16

## Engineering rule

Root before flower. A queued job, partial smoke, or UI success is not proof of the end state. A state becomes VERIFIED only when its owning runtime path and regression gates close successfully.

## Current authoritative cutover state

- `cutover_state = VERIFIED`
- `hosted_cutover_verified = true`
- `production_target = hukihbcyyqhanaqrizvm`
- `xiaoe_ai_core = uuqiwyqxllqsuboogbxh`
- Voucher runtime must never be redirected to XiaoE AI Core.

The original clean-third-project route was retired after the Supabase Free plan two-active-project limit was confirmed. The approved route is **existing-production convergence**: preserve the active Evolution production project, add compatibility boundaries, verify canonical behavior in CI, and cut the rebuilt frontend over only after production compatibility gates pass.

## Verified evidence

- Free Supabase Runtime Smoke #127: full success on QR-scanner production lineage, including migrations, SQL contracts, signed Auth flow, Edge trusted-boundary tests, Partner Staff lifecycle, Admin controls, and Browser E2E.
- GitHub Pages deployment #271 completed successfully for commit `24b42530822d9d079bb3abb3841dbd497e2b07bc`.
- Production Public Smoke #2 completed successfully against the deployed public Pages surface.
- Production Admin browser smoke verified Admin identity and authoritative dashboard data against production.
- Production Partner browser smoke verified Partner identity, tenant isolation, and Partner summary against production.
- Production Staff browser smoke verified Staff identity and branch/role context against production.
- Staff QR Scan successfully parsed a real Voucher and enforced branch restrictions on a not-allowed branch.
- Staff branch-aware Verify successfully returned `Voucher is eligible for redemption` for a valid Voucher in the allowed Staff/branch context without redeeming it.
- Public Voucher browser smoke rendered a valid production Voucher with Voucher Code, Type, Customer, Partner, Expiry, Issued Date, and Redeemable Branches.
- Production baseline was rechecked after browser smoke and remained 43 Vouchers / 8 Redemptions.
- Historical `TEST-MINES-001` / redemption pair was confirmed to predate this cutover and was not created by current smoke activity.
- Production Edge audit classified differences correctly: `voucher-engine` matches GitHub current; `manage-partner-staff`, `reset-partner-password`, and `admin-set-partner-staff-limit` retain intentional hosted compatibility implementations.
- Browser configuration uses only the modern `sb_publishable_...` key. No service-role credential is permitted in frontend code.

## Current frontend state

The verified production frontend configuration is:

- project ID: `hukihbcyyqhanaqrizvm`
- Supabase URL: `https://hukihbcyyqhanaqrizvm.supabase.co`
- browser key type: modern `sb_publishable_...`
- site base: `https://evo-voucher.github.io/evolution-optical-voucher/`
- environment: `production`

Any other project ID, XiaoE AI Core reference, service-role/secret material, or non-HTTPS backend must fail preflight.

## Verification status

All cutover gates are closed:

1. Hosted Cutover Preflight passes in production mode.
2. Free Supabase Runtime Smoke passes.
3. GitHub Pages deployment succeeds on the QR-scanner production lineage.
4. Public deployed pages load the production backend configuration.
5. Real browser smoke verifies Admin Sign In, Partner Sign In, Staff Sign In, Staff branch-aware Verify, QR Scan, and public Voucher rendering against production.
6. Production baseline is rechecked after smoke and no unintended residue exists.

Therefore:

- `cutover_state = VERIFIED`
- `hosted_cutover_verified = true`

## Architecture invariants

- Stable Core owns identity, Voucher state, redemption state, and durable relationships.
- Hosted Compatibility owns legacy production semantics such as hosted identity tables and status translations.
- Environment adapters translate between canonical and hosted implementations; Portal code must not own lineage-specific assumptions.
- Browser code receives only publishable credentials, never service-role credentials.
- High-impact mutations stay behind narrow authenticated RPC / Edge boundaries.
- Frontend presentation cannot widen authorization or redemption scope.
- Patch chains must consolidate into explicit ownership boundaries instead of accumulating overrides.

## Rollback

If a later deployment or browser verification fails, restore `assets/js/backend-config.js` to fail-closed first when the failure can expose users to a broken path, then diagnose the owning layer. Do not patch production data to force a green result.
