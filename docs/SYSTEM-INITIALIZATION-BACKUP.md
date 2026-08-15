# Evolution Voucher — System Initialization Backup v1

## Purpose

This backup model preserves the **system initialization structure**, not live production business data.

The recovery target is: from a fresh Supabase project + the GitHub repository, reconstruct a clean Evolution Voucher environment with the same database structure, security boundaries, Edge Functions, frontend, baseline configuration, and verification suite.

This document is intentionally safe for a public repository. It must never contain customer data, Partner credentials, service-role keys, API secrets, production JWTs, passwords, private tokens, or raw production dumps.

## Source of Truth

The initialization backup is composed of these repository-controlled assets:

1. `supabase/migrations/`
   - Authoritative database schema evolution.
   - Tables, constraints, indexes, triggers, RLS, RPCs, audit rules, Voucher Engine rules, snapshot rules, allocation rules, tenant boundaries.

2. `supabase/functions/`
   - Authoritative Edge Function source.
   - Trusted server-side operations stay here; secrets are injected at deployment time and never committed.

3. `supabase/config.toml`
   - Local Supabase development/runtime configuration.

4. Frontend application files
   - Admin / Voucher Engine / Partner / Staff / public Voucher pages.
   - `assets/js/backend-config.js` must remain fail-closed until a target project is explicitly configured.

5. `supabase/tests/` and `.github/workflows/`
   - Recovery verification layer.
   - A reconstructed system is not accepted merely because migrations apply; the full runtime smoke suite must pass.

6. `recovery/system-init-manifest.json`
   - Machine-readable initialization contract and recovery gates.

## What this backup DOES preserve

- Database structure and migration history.
- RLS and authorization model.
- Admin / Partner / Partner Staff / Evolution Staff realm boundaries.
- Voucher templates / versions schema and business-rule engine.
- Allocation validity modes and FEFO behavior.
- Frozen Voucher presentation and branch snapshots.
- Redemption rules and audit structures.
- Edge Function source.
- Frontend source.
- CI/E2E verification logic.
- Safe branch baseline definition when represented as non-secret seed/reference data.
- Recovery procedure and production cutover gates.

## What this backup DOES NOT preserve

- Existing production customer records.
- Existing issued Vouchers or redemption history.
- Existing Partner/Staff passwords or Auth sessions.
- Supabase secrets or service-role credentials.
- SMTP/API provider secrets.
- Any private Storage object not separately exported.

This distinction is deliberate. This is a **factory-image / clean-system recovery backup**, not a live-data disaster-recovery dump.

## Clean Recovery Procedure

### Phase A — Create fresh target

1. Create a new Supabase project.
2. Record the new project ID and URL privately.
3. Do not point the public frontend at it yet.
4. Do not reuse a legacy production service-role key.

### Phase B — Rebuild database

Apply the repository migrations in their canonical order.

Expected result:
- all migrations apply without manual table editing;
- RLS remains enabled where designed;
- narrow RPC boundaries exist;
- no browser-facing service-role dependency is introduced.

### Phase C — Deploy trusted runtime

Deploy the Edge Functions from `supabase/functions/`.

Configure required secrets through the target Supabase environment only. Never commit secret values into GitHub.

### Phase D — Initialize identities and baseline data

Create fresh operational identities:
- Admin Auth account + active `admin_users` row;
- Evolution Staff accounts as required;
- Partner accounts as required.

Use the approved Evolution Optical branch baseline as initialization/reference data. Do not restore obsolete test fixtures as production data.

### Phase E — Configure frontend target

Only after the backend passes verification:

- set the new Supabase URL;
- set the public/publishable key;
- set the new project ID;
- set `siteBase` to the intended GitHub Pages/custom-domain origin;
- keep `service_role` server-only.

Before explicit configuration, frontend pages must remain fail-closed.

### Phase F — Verify before cutover

Run the full local/recovery verification suite. Minimum acceptance gates:

- migrations rebuild successfully;
- SQL contracts pass;
- signed GoTrue core flow passes;
- Edge trusted-boundary tests pass;
- Partner Staff lifecycle passes;
- Admin controls pass;
- Browser E2E suites pass;
- migration-state check passes;
- teardown completes cleanly.

Then perform a target-project production smoke flow:

`Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption`

Only after the exact target environment passes this flow may `hosted_cutover_verified` become true.

## Safety Invariants

- Legacy production must not be modified during recovery rehearsal.
- XiaoE AI Core must never receive Evolution Voucher migrations.
- `partner_id` is derived from authenticated server-side identity, never trusted from browser input.
- `service_role` is never embedded in HTML/JS/public GitHub.
- Published Version and issued Voucher snapshots are treated as immutable business history.
- Recovery must use migrations/RPCs rather than hand-editing production tables.
- A successful migration alone is not equivalent to a successful recovery.

## Versioning Rule

Each material architecture change must update either:

- migrations,
- Edge Functions,
- frontend source,
- tests,
- or this initialization contract.

The Git commit SHA is the immutable version identifier of a recoverable system state.

## Recovery Definition of Done

A system initialization backup is considered **RECOVERABLE** only when a clean environment can be recreated from repository assets and the full verification suite passes without depending on hidden manual fixes.

A system initialization backup is considered **PRODUCTION RESTORABLE** only after the chosen hosted target also passes the end-to-end production smoke flow.
