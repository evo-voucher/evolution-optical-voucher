# Evolution Voucher Runtime Deployment Preflight v1

Status: PREPARED, NOT EXECUTED.

This runbook exists to prevent an accidental deployment into the legacy Evolution Voucher production database or the XiaoE AI Core memory database.

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
At the time this preflight was prepared, the connected Supabase account exposed only two projects:

- `hukihbcyyqhanaqrizvm` — legacy Evolution Voucher production — DO NOT MIGRATE.
- `uuqiwyqxllqsuboogbxh` — XiaoE AI Core — MEMORY ONLY, DO NOT MIGRATE.

Therefore no verified new runtime target currently exists in the connected account.

## Migration package
The current staged reconstruction chain ends at:

`037_reporting_status_precedence.sql`

Apply every file in `supabase/migrations/` strictly in numeric order. Never skip directly to a later migration because many later files intentionally override earlier compatibility implementations.

## Pre-migration blank-target checks
On the verified new target only:

- inspect existing migration history;
- confirm Evolution Voucher business tables do not already exist unless this is a deliberate retry of the same reconstruction deployment;
- confirm no unrelated application schema will be overwritten;
- record project ID, region and timestamp in the deployment record.

## Post-migration static checks
Run the non-destructive SQL tests in `supabase/tests/` beginning with:

- `001_contract_smoke_checks.sql`
- `002_security_boundary_audit.sql`
- `003_partner_isolation_constraints.sql`
- `004_admin_mutation_contract.sql`
- `005_admin_control_directory_contract.sql`
- `006_partner_catalog_contract.sql`
- `007_atomic_engine_admin_contract.sql`
- `008_partner_issuance_contract.sql`
- `009_identity_realm_registry_contract.sql`
- `010_staff_operational_contract.sql`
- `011_public_voucher_contract.sql`
- `012_partner_quota_contract.sql`
- `013_reporting_status_precedence_contract.sql`

Any failed security, ownership, quota, identity-realm, or transaction-boundary check is a STOP condition.

## Runtime identity fixtures
Create disposable test identities only after schema checks pass:

- one Admin;
- Partner A admin;
- Partner A staff user;
- Partner B admin;
- one branch Staff;
- one Manager;
- one All Branch Manager.

Never reuse real customer or production credentials for initial runtime proof.

## Mandatory end-to-end proof
Execute this complete flow on disposable data:

Admin Allocate -> Partner Catalog -> Partner Issue -> Customer Public Voucher -> Staff Verify -> Staff Redeem -> Admin/Partner/Staff Reporting -> Admin Reverse -> Reporting reconciliation.

Also prove:

- Partner A cannot see or issue from Partner B ownership;
- positive Partner voucher limit cannot be exceeded under concurrent issuance;
- voucher_limit=0 remains unlimited;
- Allocation and Version supply cannot be exceeded under concurrent issuance;
- concurrent double redemption cannot exceed usage_limit;
- branch restrictions are enforced;
- revoked/expired/redeemed/active reporting buckets are mutually exclusive;
- reversal preserves the redemption record and restores usage correctly;
- anonymous public lookup exposes no sensitive fields;
- one Auth UID cannot become active in two operational realms concurrently.

## Edge Function gate
Deploy only the Edge Functions required by the reconstructed Admin/server flows. JWT verification stays enabled for authenticated operational functions. `service_role` remains server-only and must never be present in browser code.

## Frontend cutover gate
Only after every migration and runtime gate passes:

1. obtain the verified target project URL;
2. obtain an enabled publishable key only;
3. update `assets/js/backend-config.js` with exact project ID, URL and publishable key;
4. set `enabled: true`;
5. validate Admin, Partner, Staff and Public pages against the new target;
6. verify the browser never contains a service_role key;
7. keep legacy production untouched for rollback/reference.

## Rollback principle
Before frontend cutover, rollback is simply: do not enable the reconstructed frontend. The legacy production project remains unchanged. After cutover, rollback must prefer frontend re-point/disable and database-preserving remediation over destructive cleanup.

## XiaoE stop gate
No runtime deployment may begin merely because the migration package is ready. Exact target identity is a zero-assumption zone. If the verified new target does not exist, preparation may continue, but deployment must stop.