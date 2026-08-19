# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-19

## Engineering rule

Root before flower. A queued job, partial smoke, or UI success is not proof of the end state. A state becomes VERIFIED only when its owning runtime path and regression gates close successfully.

## Current authoritative target state

- `cutover_state = VERIFIED_HISTORICAL_BASELINE`
- `hosted_cutover_verified = true`
- `production_target = xfivcfwexcxsyiylgryn`
- `previous_verified_target = hukihbcyyqhanaqrizvm`
- `xiaoe_ai_core = uuqiwyqxllqsuboogbxh`
- Voucher runtime must never be redirected to XiaoE AI Core.

The original 2026-08-16 hosted cutover was verified against `hukihbcyyqhanaqrizvm`. On 2026-08-18 commit `cebae630fb41e7222c8ba1deed8761a044fa7f76` deliberately changed `assets/js/backend-config.js` from `hukihbcyyqhanaqrizvm` to `xfivcfwexcxsyiylgryn` with the commit message `Point production frontend to canonical Supabase backend`.

Therefore the 2026-08-16 `hukih...` values below remain historical cutover evidence, while the current repository Production target contract is `xfivcfwexcxsyiylgryn`.

## Historical verified cutover evidence — 2026-08-16

The original cutover route was **existing-production convergence**: preserve the active Evolution production project, add compatibility boundaries, verify canonical behavior in CI, and cut the rebuilt frontend over only after production compatibility gates pass.

Verified evidence from that cutover:

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
- Browser configuration used only the modern `sb_publishable_...` key. No service-role credential is permitted in frontend code.

This historical evidence must not be reinterpreted as proof that the later `xfiv...` target has the same 43 Voucher / 8 Redemption baseline.

## Current frontend target state

Current repository Production configuration is:

- project ID: `xfivcfwexcxsyiylgryn`
- Supabase URL: `https://xfivcfwexcxsyiylgryn.supabase.co`
- browser key type: modern `sb_publishable_...`
- site base: `https://evo-voucher.github.io/evolution-optical-voucher/`
- environment: `production`
- target-intent evidence: commit `cebae630fb41e7222c8ba1deed8761a044fa7f76`

The currently connected Supabase account can access `xfivcfwexcxsyiylgryn`, where the environment audit observed 2 partners, 7 branches, 1 voucher, 1 redemption and 2 voucher versions. Those counts are evidence about `xfiv...`; they are not expected to match the historical `hukih...` baseline.

Any XiaoE AI Core reference, service-role/secret material, non-HTTPS backend, or unexplained target drift must fail the environment/release gate.

## Verification status

The 2026-08-16 cutover remains a VERIFIED historical baseline for `hukih...`.

The current repository target migration to `xfiv...` is **SOURCE-INTENT VERIFIED** because the explicit target-change commit and current root backend config agree. Final current-runtime verification still requires the Production Public Smoke to pass against the deployed GitHub Pages surface using the updated `xfiv...` expectation.

Current release rule:

1. Environment Contract Gate must show root Production config, Readiness target and Production Smoke target agree on `xfivcfwexcxsyiylgryn`.
2. Deployment/runtime smoke must confirm the public GitHub Pages surface actually serves that target.
3. If runtime differs, do not rewrite data or weaken guards; diagnose deployment/cache/source ownership and recover to a known-good state.

## Architecture invariants

- Stable Core owns identity, Voucher state, redemption state, and durable relationships.
- Hosted Compatibility owns legacy production semantics such as hosted identity tables and status translations where still applicable.
- Environment adapters translate between canonical and hosted implementations; Portal code must not own lineage-specific assumptions.
- Browser code receives only publishable credentials, never service-role credentials.
- High-impact mutations stay behind narrow authenticated RPC / Edge boundaries.
- Frontend presentation cannot widen authorization or redemption scope.
- Patch chains must consolidate into explicit ownership boundaries instead of accumulating overrides.

## Rollback

If a later deployment or browser verification fails, restore `assets/js/backend-config.js` to a known-good fail-closed or verified target state first when the failure can expose users to a broken path, then diagnose the owning layer. Do not patch Production data to force a green result.
