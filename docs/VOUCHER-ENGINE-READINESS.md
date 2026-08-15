# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-15

## Engineering rule

Root before flower. Do not treat a hypothesis, partial step, queued CI job, or UI success message as proof of the end state. A change is VERIFIED only when the relevant runtime path and the full regression workflow close successfully.

## Verified local runtime baseline

The disposable local Supabase CI baseline has verified the following core invariants:

- Auth-derived operational realms for Admin, Partner Admin, Partner Staff, and Evolution Staff.
- Partner identity is derived from Auth / partner_users; the browser cannot supply or override partner_id during Voucher issuance.
- Voucher Template / immutable Version / Partner Allocation / issued Voucher Snapshot separation.
- FROM ISSUE validity with true calendar-month arithmetic.
- FROM ALLOCATION validity with arbitrary positive day counts and rejection of non-positive values.
- Multiple allocation batches use earliest-expiry-first consumption for allocation-anchored stock.
- Issued Voucher validity, Theme, Greeting, Terms, and branch IDs are frozen snapshots.
- Final issued redemption scope is the intersection of Partner claim scope, Version scope, and Allocation scope.
- Version and Allocation branch scopes are independently configurable by Admin; an Allocation does not mutate Partner global claim scope.
- An issued all-branches Voucher does not gain branches that are created later.
- Partner WhatsApp sharing uses the frozen issued Voucher snapshot and appends the customer Voucher URL from the configured site base.
- Public customer Voucher rendering exposes the frozen Theme, approved Greeting, optional occasion Greeting, Terms, and snapshotted branch details.
- Public presentation configuration is constrained to safe whitelisted values rather than raw HTML/script/arbitrary CSS execution.
- Admin Voucher Engine UI can create classifications/templates, publish immutable Versions, configure validity/presentation/Version scope, and allocate stock with Allocation scope.
- Admin navigation to Voucher Engine, Evolution Staff, and Partner password tools is browser-tested.
- The repository has passed clean local recovery from migrations and runtime assets without hidden manual database repair.
- Hosted cutover preflight is executed by CI, not merely stored as a script.
- Clean recovery preserves both runtime assets and hosted-cutover safety assets, including the cutover runbook and preflight contract.

## Key runtime evidence

- Partner WhatsApp browser E2E: `supabase/tests/browser/006_partner_whatsapp_share_e2e.mjs`
- Admin Voucher Engine browser E2E: `supabase/tests/browser/007_admin_voucher_engine_e2e.mjs`
- Public Voucher presentation browser E2E: `supabase/tests/browser/008_public_voucher_presentation_e2e.mjs`
- Admin navigation browser E2E: `supabase/tests/browser/009_admin_navigation_e2e.mjs`
- Voucher delivery snapshot runtime E2E: `supabase/tests/025_voucher_delivery_runtime_e2e.sql`
- Allocation FEFO / future-branch freeze E2E: `supabase/tests/026_voucher_allocation_fefo_and_branch_freeze_e2e.sql`
- Allocation branch-scope runtime E2E: `supabase/tests/026_allocation_branch_scope_runtime_e2e.sql`
- Partner Staff tenant / branch non-broadening E2E: `supabase/tests/027_partner_staff_tenant_branch_non_broadening_e2e.sql`
- Recovery manifest contract: `supabase/tests/runtime/002_recovery_manifest_contract.sh`
- Hosted cutover preflight contract: `supabase/tests/runtime/003_hosted_cutover_preflight_contract.sh`
- Hosted cutover runbook: `docs/HOSTED-CUTOVER-RUNBOOK.md`

Latest verified full local workflow evidence:

- Run `31883788838`
- Job `95009948898`
- Head `eaae937436f60e1c0f7e3541784355ac7618e103`
- Conclusion: success

Key milestones within the same verified baseline:

- Clean-rebuild recovery verified in Run `31879716239`, Job `95000488980`, Head `e1b24d5078ad97bd41e7cf70848363c45d66a866`.
- Three-layer branch-scope architecture verified in Run `31880492960`, Job `95002270064`, Head `a7935d77fb646b64fa6eaf38637948e58bb6e1be`.
- Hosted preflight actual CI execution verified in Run `31883329270`, Job `95008834856`, Head `0723cf581faec383340452b424d64a1279c28ef5`.
- Recovery preservation of hosted-cutover safety assets verified in Run `31883788838`, Job `95009948898`, Head `eaae937436f60e1c0f7e3541784355ac7618e103`.

## Approved customer share intro

The default issued Voucher greeting is:

```text
Hi 👋
A little gift for you 🎁✨
Here is your Evolution Optical Voucher.
```

An occasion greeting such as Birthday / Raya / Merdeka / Christmas may be appended by the Version and is frozen at issuance.

## Hosted cutover gate — NOT VERIFIED YET

Local CI success does **not** mean the hosted production cutover is complete.

Before commercial hosted use, all of the following must be explicitly verified against the intended new Voucher Supabase target:

1. Confirm the exact hosted target project ID and environment ownership.
2. Confirm no migration or frontend config is pointed at the XiaoE AI Core project.
3. Confirm the legacy Evolution production project remains untouched during preparation.
4. Apply migrations to the intended new Voucher target only.
5. Deploy required Edge Functions to that same target.
6. Configure frontend `backend-config.js` with the intended hosted URL, publishable key, project ID, and site base; never expose service-role credentials.
7. Create/verify the Admin identity and branch baseline in the target.
8. Run hosted smoke checks for Admin login, Partner login, Partner Staff issuance, WhatsApp share, public Voucher lookup, Staff verify/redeem, and Admin reporting.
9. Verify RLS / RPC behavior using signed real hosted sessions, not only SQL service-role checks.
10. Verify rollback / recovery procedure before switching any public entry point.

The authoritative hosted launch sequence is maintained in `docs/HOSTED-CUTOVER-RUNBOOK.md` and its safety assumptions are enforced by `supabase/tests/runtime/003_hosted_cutover_preflight_contract.sh`.

Until those hosted checks pass, the authoritative state remains:

- `hosted_cutover_verified = false`
- legacy production must not be mutated as part of this preparation
- frontend backend configuration remains fail-closed
- no existing Supabase project is implicitly treated as the new Voucher target

## Architecture invariants

- Stable Core owns identity, Voucher state, redemption state, and durable relationships.
- Voucher Version owns customer offer and presentation policy.
- Partner Allocation owns Partner stock, Allocation branch scope, and allocation-relative validity clock when used.
- Issued Voucher Snapshot owns immutable customer-facing truth after issuance.
- Browser code does not receive service-role credentials.
- High-impact mutations go through narrow Admin or trusted Edge/RPC boundaries.
- Frontend presentation must not be able to widen authorization or redemption scope.
- Recovery must restore both execution assets and the hosted-cutover safety boundary.

## Remaining work before hosted launch

The remaining work is now predominantly environment-specific rather than core-engine architecture:

- nominate a clean hosted Voucher Supabase target;
- run the hosted cutover procedure against that exact target;
- deploy Edge Functions and configure only public frontend credentials for that target;
- initialize real Admin / branch baseline / required Partner accounts;
- perform the exact production E2E smoke flow;
- complete final mobile wording/user-acceptance review against the hosted environment.

This document records the verified local architecture and the remaining hosted cutover boundary. It must not be used as evidence that hosted production is already live.
