# Evolution Voucher Runtime Deployment Preflight v1

Status: PREPARED, NOT EXECUTED.

This runbook exists to prevent accidental deployment into the legacy Evolution Voucher production database or the XiaoE AI Core memory database.

## Hard target gate
Before any migration is applied, all of the following must be true:

1. Supabase project is explicitly identified as the NEW Evolution Voucher reconstruction target.
2. Project ID is not `hukihbcyyqhanaqrizvm` (legacy Evolution Voucher production).
3. Project ID is not `uuqiwyqxllqsuboogbxh` (XiaoE AI Core memory project).
4. Target is confirmed blank/new for this reconstruction.
5. Region and organization are verified.
6. No frontend key or URL is changed yet.

If any item is unknown, STOP. Do not apply migrations.

## Current environment observation
Latest connected-account verification still exposes only two hosted projects:

- `hukihbcyyqhanaqrizvm` — legacy Evolution Voucher production — DO NOT MIGRATE.
- `uuqiwyqxllqsuboogbxh` — XiaoE AI Core — MEMORY ONLY, DO NOT MIGRATE.

Therefore no verified new hosted runtime target currently exists in the connected account.

## Migration package
The staged reconstruction chain currently ends at:

`041_serialize_voucher_version_publish.sql`

Apply every file in `supabase/migrations/` strictly in numeric order. Never skip directly to a later migration because later files intentionally harden or supersede earlier compatibility implementations.

Important late-stage ownership points:

- 038 owns atomic Partner/Evolution Staff business-profile provisioning behind narrow server-only RPCs.
- 039 owns Partner Staff lifecycle mutations and tenant-derived staff-limit enforcement.
- 040 owns authenticated Admin password-reset audit recording.
- 041 owns per-Template Voucher Version publication serialization before allocating `version_no`.

## Pre-migration blank-target checks
On the verified new target only:

- inspect existing migration history;
- confirm Evolution Voucher business tables do not already exist unless this is a deliberate retry of the same reconstruction deployment;
- confirm no unrelated application schema will be overwritten;
- record project ID, region, organization and timestamp in the deployment record.

## Post-migration static checks
Run every SQL contract under `supabase/tests/*.sql` with `ON_ERROR_STOP=1`.

The current contract suite runs through:

`020_voucher_version_publish_concurrency_contract.sql`

Any failed security, ownership, quota, identity-realm, serialization, authorization, or transaction-boundary check is a STOP condition.

## Runtime identity fixtures
Use disposable identities only after schema checks pass:

- one Admin;
- Partner A admin;
- Partner B admin;
- Partner Staff where required;
- one Evolution branch Staff;
- Manager / All Branch Manager fixtures when testing their specific permissions.

Never reuse real customer or production credentials for initial runtime proof.

## Mandatory runtime proof
The free local-Supabase CI path must pass from a clean rebuild and includes:

1. `supabase start`.
2. `supabase db reset` through migration 041.
3. all SQL contracts through 020.
4. real parallel Voucher Version publish proof using two independent PostgreSQL sessions against the same Template; both publishes must succeed as distinct sequential versions and `current_version_id` must point to the latest version.
5. signed GoTrue signup/login -> JWT -> PostgREST RPC core flow.
6. local Edge Function trusted-boundary tests.
7. Partner Staff lifecycle Edge tests.
8. Admin Edge controls.
9. real browser Portal E2E: Partner login -> issue -> Public Voucher -> Staff verify/redeem -> Public redeemed state -> Admin reporting.

The browser flow must use the same canonical Voucher identity throughout. A successful Staff redemption must leave an explicit visible outcome even after the transient redeem form is closed.

## Security / business proofs
Also prove on the target runtime:

- Partner A cannot see or issue from Partner B ownership;
- positive Partner voucher limit cannot be exceeded under concurrent issuance;
- `voucher_limit=0` remains unlimited;
- Allocation and Version supply cannot be exceeded under concurrent issuance;
- concurrent Voucher Version publication is serialized per Template rather than recovered by retry logic;
- concurrent double redemption cannot exceed `usage_limit`;
- branch restrictions are enforced;
- revoked/expired/redeemed/active reporting buckets are mutually exclusive;
- reversal preserves the redemption record and restores usage correctly;
- anonymous public lookup exposes no sensitive fields;
- one Auth UID cannot become active in two operational realms concurrently;
- original signed caller JWT owns authorization decisions; service credentials are reserved for narrow trusted server actions;
- broad direct service-role business-table DML remains closed.

## Edge Function gate
Deploy only required reconstructed Edge Functions. JWT verification stays enabled for authenticated operational functions. `service_role` remains server-only and must never be present in browser code.

## Frontend cutover gate
Only after the hosted target exists and every migration/runtime gate passes against that exact target:

1. obtain the verified target project URL;
2. obtain an enabled publishable key only;
3. update `assets/js/backend-config.js` with exact project ID, URL and publishable key;
4. set `enabled: true`;
5. validate Admin, Partner, Staff and Public pages against the hosted target;
6. verify the browser never contains a service-role key;
7. keep legacy production untouched for rollback/reference.

Portal HTML and shared frontend JS changes must continue to trigger the integrated runtime smoke workflow.

## Rollback principle
Before frontend cutover, rollback is simply: do not enable the reconstructed frontend. The legacy production project remains unchanged. After cutover, rollback should prefer frontend re-point/disable and database-preserving remediation over destructive cleanup.

## Architecture rule
No patch-driven cutover fixes. A failed gate is investigated through the root-cause path: reproduce -> trace full path -> identify authoritative owning layer -> prove root cause -> fix the owning layer -> remove workaround logic -> rerun regression proof.

Keep extension paths open without premature abstraction: Stable Core remains small; new behaviors should prefer versioned modules, configuration, narrow RPCs, adapters/providers, capability flags and composable rules rather than hardcoded business forks.

## XiaoE stop gate
No runtime deployment may begin merely because the migration package is ready. Exact target identity is a zero-assumption zone. If the verified new hosted target does not exist, preparation and local proof may continue, but deployment must stop.
