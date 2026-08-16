# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-16

## Engineering rule

Root before flower. A queued job, migration application, or UI success is not proof of the end state. A state becomes VERIFIED only when its owning runtime path and regression gates close successfully.

## Current authoritative cutover state

- `cutover_state = CUTOVER_IN_PROGRESS`
- `hosted_cutover_verified = false`
- `production_target = xfivcfwexcxsyiylgryn`
- `xiaoe_ai_core = uuqiwyqxllqsuboogbxh`
- Voucher runtime must never be redirected to XiaoE AI Core.

The approved route is **canonical reconstruction**: GitHub remains the Voucher frontend, Supabase project `xfivcfwexcxsyiylgryn` is the reconstructed Voucher backend, and XiaoE AI Core remains a separate system boundary.

## Verified evidence so far

- Canonical Voucher schema and migrations 001-046 are present in the reconstructed Supabase backend.
- First Admin bootstrap completed successfully: one Auth user, one active Admin identity, one Admin operational realm, and the one-time bootstrap code is consumed/disabled.
- Seven Evolution branches are present.
- Core business tables have RLS enabled; anon has no direct business-table privileges and authenticated users have no direct business-table write privileges.
- Service provisioning functions for Admin bootstrap, Partner provisioning, and Evolution Staff provisioning are executable only by `service_role`.
- Edge Functions for Partner, Staff, password reset, Voucher Engine, and staff-limit management require JWT; the bootstrap function is the intentional exception and performs its own one-time bootstrap validation.
- Database integrity audit currently reports no orphan Partner users, Staff users, Vouchers, Redemptions, Voucher-Branch mappings, or operational realms.
- `verify_voucher()` and `redeem_voucher()` now share the same branch-snapshot semantics.
- Partner WhatsApp/public share branch scope is aligned with the issued Voucher branch snapshot.
- Browser configuration contains only a publishable Supabase key; service-role credentials are forbidden.
- Official Partner issuance uses `issue_engine_voucher()` and derives Partner tenant identity from Auth rather than a browser-supplied `partner_id`.

## Remaining gates before VERIFIED

1. Finish source hardening and retire legacy operational entry points that still target the previous Supabase project.
2. Ensure QR redemption records `redeem_method = qr` rather than `manual_code` when the scanner was used.
3. Tighten Partner and Staff portal realm checks to their exact operational realm.
4. Align production smoke/preflight configuration with project `xfivcfwexcxsyiylgryn`.
5. Run automated repository/runtime contracts against the canonical release candidate.
6. Complete controlled end-to-end UAT:
   `Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`.
7. Perform final phone/browser checks for iPhone Safari/PWA, camera QR permission/scan, and actual WhatsApp share rendering.
8. Recheck database residue and integrity after UAT.

Until all gates close, do not mark this reconstruction VERIFIED and do not treat the old hosted production evidence as evidence for the new canonical backend.

## Current frontend release candidate

- project ID: `xfivcfwexcxsyiylgryn`
- Supabase URL: `https://xfivcfwexcxsyiylgryn.supabase.co`
- browser key type: modern `sb_publishable_...`
- site base: `https://evo-voucher.github.io/evolution-optical-voucher/`
- environment: `production` on the cutover release-candidate branch only

The public `main` branch must not be switched to this backend until the remaining gates are complete.

## Architecture invariants

- GitHub owns the frontend; Supabase owns database/Auth/RLS/Edge backend behavior.
- XiaoE AI Core is separate from Evolution Voucher and must never receive Voucher runtime migrations or production traffic.
- Browser code receives only publishable credentials, never service-role credentials.
- High-impact mutations stay behind narrow authenticated RPC / Edge boundaries.
- Partner/Staff tenant and branch scope are derived and verified server-side.
- Frontend presentation cannot widen authorization or redemption scope.
- One canonical Voucher issuance engine is preferred over parallel legacy issuance paths.

## Rollback

If a later deployment or browser verification fails, restore `assets/js/backend-config.js` to the last known-good or fail-closed configuration before changing business data. Preserve logs and diagnose the owning layer. Do not patch production data merely to force a green test.
