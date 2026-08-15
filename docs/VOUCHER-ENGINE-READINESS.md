# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-16

## Engineering rule

Root before flower. A queued job, partial smoke, or UI success is not proof of the end state. A state becomes VERIFIED only when its owning runtime path and regression gates close successfully.

## Current authoritative cutover state

- `cutover_state = CUTOVER_IN_PROGRESS`
- `hosted_cutover_verified = false`
- `production_target = hukihbcyyqhanaqrizvm`
- `xiaoe_ai_core = uuqiwyqxllqsuboogbxh`
- Voucher runtime must never be redirected to XiaoE AI Core.

The original clean-third-project route was retired after the Supabase Free plan two-active-project limit was confirmed. The approved route is now **existing-production convergence**: preserve the active Evolution production project, add compatibility boundaries, verify canonical behavior in CI, and cut the rebuilt frontend over only after production compatibility gates pass.

## Verified evidence before frontend activation

- Free Supabase Runtime Smoke #122: full success, including migrations, SQL contracts, Auth flow, Edge trusted-boundary tests, Partner Staff lifecycle, Admin controls, and Browser E2E.
- Production baseline preserved after security hardening: 43 Vouchers / 8 Redemptions.
- Migration `060_restrict_legacy_test_voucher_rpc` removed authenticated access to the orphaned test RPC while retaining service-role recovery access.
- Production Admin Auth-context smoke: realm=admin and dashboard reports 5 Partners / 43 Vouchers / 8 completed Redemptions.
- Production Partner Auth-context smoke: Partner realm, summary, recent Vouchers, and issuable catalog verified.
- Production Staff Auth-context smoke: All Branch Manager realm, seven-branch context, redemption history, and real Voucher verification verified.
- Real Staff verify against `EO-20260815-83B3B894` at MINES returned success, branch_allowed=true, can_redeem=true without redeeming or writing business data.
- Production Edge audit classified differences correctly: `voucher-engine` matches GitHub current; `manage-partner-staff`, `reset-partner-password`, and `admin-set-partner-staff-limit` retain intentional hosted compatibility implementations.
- No service-role credential is permitted in browser configuration.

## Current frontend state

The production frontend configuration may be enabled only during `CUTOVER_IN_PROGRESS` when all of these are exact:

- project ID: `hukihbcyyqhanaqrizvm`
- Supabase URL: `https://hukihbcyyqhanaqrizvm.supabase.co`
- browser key type: modern `sb_publishable_...`
- site base: `https://evo-voucher.github.io/evolution-optical-voucher/`
- environment: `production`

Any other project ID, XiaoE AI Core reference, service-role/secret material, or non-HTTPS backend must fail preflight.

## Remaining gate before VERIFIED

`hosted_cutover_verified` stays `false` until all of the following close on the production frontend commit:

1. Hosted Cutover Preflight passes in production mode.
2. Free Supabase Runtime Smoke passes.
3. GitHub Pages deployment succeeds for the same commit lineage.
4. Public deployed pages load the production backend configuration.
5. Real browser smoke verifies Admin Sign In, Partner Sign In, Staff Sign In / verify path, and public Voucher rendering against production.
6. Production baseline is rechecked after smoke and no unintended residue exists.

Only after those gates pass may the state become:

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

If deployment or browser verification fails after frontend activation, restore `assets/js/backend-config.js` to fail-closed first, then diagnose the owning layer. Do not patch production data to force a green result.
