# Evolution Optical Voucher — Hosted Cutover Runbook

Status: PREPARED, NOT EXECUTED

This runbook defines the only approved order for moving the verified Evolution Voucher system from local/recovery validation into a real hosted Supabase target.

It is intentionally target-agnostic until a new Voucher Supabase project is explicitly nominated and approved.

## Non-negotiable boundaries

- Do not use legacy production project `hukihbcyyqhanaqrizvm` as the migration rehearsal target.
- Do not deploy Voucher migrations or runtime into XiaoE AI Core project `uuqiwyqxllqsuboogbxh`.
- Do not enable frontend backend configuration before the hosted target is explicitly approved.
- Never expose a `service_role` key in browser code, GitHub Pages, HTML, JS, or public repository files.
- Never treat successful migration application alone as proof of a successful cutover.
- Never mark `hosted_cutover_verified = true` until the exact hosted production E2E flow passes.
- Legacy production remains untouched unless a separate, explicit production-data migration plan is approved.

## Phase 0 — Target nomination

Required inputs before any hosted write:

1. New Voucher Supabase project ID.
2. New project URL.
3. Ownership / organization confirmation.
4. Region confirmation.
5. Confirmation that the target is neither legacy production nor XiaoE AI Core.
6. Explicit approval to use that target for Voucher deployment.

If any item is missing, STOP. No migration, Edge Function deployment, frontend config change, or secret upload is allowed.

## Phase 1 — Preflight proof

Before touching the hosted target:

1. Confirm latest `main` commit.
2. Confirm latest Free Supabase Runtime Smoke is green.
3. Confirm recovery manifest contract is green.
4. Confirm hosted cutover preflight contract is green.
5. Confirm `assets/js/backend-config.js` remains fail-closed.
6. Confirm repository contains no service-role credential material.
7. Record the exact commit SHA that will be deployed.

Output: deployment candidate SHA.

## Phase 2 — Hosted database initialization

Apply repository migrations to the nominated target in canonical order.

Acceptance gates:

- all migrations apply without manual table edits;
- RLS remains enabled where designed;
- Admin / Partner / Partner Staff / Evolution Staff realm boundaries exist;
- Voucher Engine RPCs and allocation/Version branch-scope rules exist;
- migration state matches repository expectation.

If any migration fails, STOP and diagnose the owning layer. Do not hand-patch the hosted database to force progress.

## Phase 3 — Trusted runtime deployment

Deploy required Edge Functions from `supabase/functions/` to the same nominated target.

Secrets are configured only in the hosted Supabase environment.

Acceptance gates:

- Edge Functions deploy successfully;
- no service-role secret is copied into frontend files;
- trusted-boundary behavior remains server-side;
- Partner identity remains Auth-derived.

## Phase 4 — Identity and baseline initialization

Create fresh hosted operational identities and baseline data:

- Admin Auth identity + active `admin_users` row;
- Evolution Staff identities as required;
- Partner identities as required;
- approved Evolution Optical branch baseline.

Do not restore old sessions, passwords, or hidden test fixtures.

## Phase 5 — Hosted signed-session verification

Using real hosted Auth sessions, verify at minimum:

1. Admin login and operational realm.
2. Partner Admin login and tenant isolation.
3. Partner Staff login and tenant isolation.
4. Evolution Staff login and branch permissions.
5. Admin Voucher Version publish.
6. Admin Allocation with Version scope and Allocation scope.
7. Partner issue flow.
8. Issued Voucher immutable snapshot behavior.
9. WhatsApp share data generation.
10. Public Voucher lookup.
11. Evolution Staff verify/redeem.
12. Admin redemption record reflects the completed redemption.

The required production smoke chain is:

`Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`

This exact chain must close successfully on the nominated hosted target.

## Phase 6 — Frontend cutover

Only after Phases 0–5 pass:

1. Set hosted Supabase URL.
2. Set public/publishable key.
3. Set project ID.
4. Set approved `siteBase`.
5. Keep `service_role` server-only.
6. Confirm all public pages load against the nominated target.
7. Re-run the exact hosted smoke chain through the real frontend.

Frontend activation is the last step, not the first.

## Phase 7 — Cutover declaration

`hosted_cutover_verified` may become `true` only when all of these are true:

- nominated target identity is recorded;
- migration state is verified;
- Edge Functions are verified;
- signed hosted Auth/RLS/RPC behavior is verified;
- browser/public flow is verified;
- exact production smoke chain passes;
- rollback path is documented and usable;
- legacy production was not mutated by the rehearsal/cutover preparation.

If even one gate is not proven, authoritative state remains:

`hosted_cutover_verified = false`

## Rollback rule

If a hosted verification step fails before public cutover:

- keep frontend pointed away from the failed target;
- do not switch public entry points;
- preserve logs/evidence;
- repair in repository/migrations/functions first;
- re-run clean verification;
- repeat hosted verification from the owning failed layer.

If a failure occurs after frontend cutover, restore the previous known-good frontend configuration first, then diagnose the hosted target. Never attempt emergency fixes by exposing privileged credentials to the browser.

## Separate concern: live operational data

This runbook covers system deployment and hosted cutover only.

It does **not** prove restoration or migration of existing live customer data, issued Vouchers, redemption history, Auth sessions, passwords, Storage objects, or secrets.

A live-state migration requires a separate approved data migration / backup plan.

## Definition of done

Hosted cutover is done only when the nominated target passes the complete production smoke chain under real hosted identities and the public frontend is verified against that exact target.

Until then, the system remains locally/recovery VERIFIED but hosted cutover UNVERIFIED.
