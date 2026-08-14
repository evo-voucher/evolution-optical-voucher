# Evolution Voucher Deployment Order v1

Status: reconstruction staging only. Do not apply to legacy production project `hukihbcyyqhanaqrizvm`.

## Source of truth
- Code and migration order: this repository.
- Business transactions after deployment: target Voucher Supabase project.
- XiaoE durable project conclusions: XiaoE AI Core `public.memories`.
- Runtime deployment safety procedure: `docs/RUNTIME_DEPLOYMENT_PREFLIGHT_V1.md`.

## Migration order
Apply migrations strictly by numeric filename order. Current staged chain:

1. `001_core_schema.sql`
2. `002_identity_and_rls.sql`
3. `003_issue_voucher_rpc.sql`
4. `004_verify_voucher_rpc.sql`
5. `005_redeem_voucher_rpc.sql`
6. `006_public_voucher_rpc.sql`
7. `007_reverse_redemption_rpc.sql`
8. `008_partner_controls.sql`
9. `009_voucher_engine_schema.sql`
10. `010_issue_engine_voucher_rpc.sql`
11. `011_frontend_compatibility_rpc.sql`
12. `012_integrity_guards.sql`
13. `013_admin_controls_rpc.sql`
14. `014_seed_branches.sql`
15. `015_reporting_source_of_truth.sql`
16. `016_voucher_engine_admin_rpc.sql`
17. `017_voucher_engine_invariants.sql`
18. `018_partner_tenant_isolation.sql`
19. `019_partner_isolation_write_guards.sql`
20. `020_scoped_reporting_rpc.sql`
21. `021_identity_realm_exclusivity.sql`
22. `022_partner_claim_response_compatibility.sql`
23. `023_reversal_authorization_v2.sql`
24. `024_engine_concurrency_hardening.sql`
25. `025_authoritative_partner_quota.sql`
26. `026_engine_lock_order_hardening.sql`
27. `027_trusted_server_tenant_boundary.sql`
28. `028_function_execute_hardening.sql`
29. `029_staff_direct_read_boundary.sql`
30. `030_declarative_partner_consistency.sql`
31. `031_admin_control_directory.sql`
32. `032_partner_issuable_catalog.sql`
33. `033_atomic_engine_admin_mutations.sql`
34. `034_identity_realm_registry.sql`
35. `035_staff_operational_context.sql`
36. `036_canonical_partner_voucher_quota.sql`
37. `037_reporting_status_precedence.sql`

## Dependency checkpoints
- 002 requires core identity/business tables from 001.
- 009 requires `branches`, `partners`, and `vouchers` from 001 plus identity helpers from 002 for RLS policies.
- 010 requires Voucher Engine tables from 009.
- 011 routes legacy Partner issuance entrypoints into 010.
- 012 requires engine tables already present because it installs `updated_at` triggers on them.
- 015 requires vouchers/redemptions/partners/branches.
- 016/017 require engine schema from 009.
- 018/019 require both core and engine tenant tables.
- 020 requires identity helpers and tenant tables.
- 021 requires all three live identity realms: admin_users, partner_users, staff_users.
- 022 overrides the Partner claim response from 008 without changing its source of truth.
- 023 deliberately overrides the reversal and voucher immutability functions created in 007/012.
- 024 installs insert-time capacity protection after engine tables and issuance RPCs exist.
- 025 is historical quota cleanup but is superseded by 036 for zero-limit semantics.
- 026 deliberately overrides the 024 capacity guard to use Version advisory locking before Allocation row locking and re-check Version active status at the insert boundary.
- 027 resolves the trusted-server interaction with 019: Partner/browser requests remain tenant-bound, while verified `service_role` server requests may perform cross-Partner Admin operations after caller authorization in the Edge Function. It does not weaken data-consistency guards.
- 028 removes PostgreSQL's default PUBLIC function EXECUTE exposure, preserves explicit authenticated/service_role grants, and re-allows anon only for `get_public_voucher(uuid)`.
- 029 removes Staff direct SELECT paths to Voucher/Redemption/branch-mapping detail. Staff operational reads are served through scoped RPCs from 004/005/020; Admin and owning Partner direct read scopes remain.
- 030 adds declarative composite foreign keys so Voucher allocation ownership, Redemption ownership, and Allocation Event tenant/version identity cannot cross Partner boundaries even under trusted server/service-role writes.
- 031 adds Admin-only read models `admin_partner_directory()` and `admin_active_branches()` so Admin control UI can render Partner/branch management without restoring browser direct-table reads.
- 032 adds `partner_issuable_voucher_catalog()` so Partner UI can discover only active, authorized, currently allocated Voucher Versions with remaining allocation/supply, without direct reads of global Voucher Engine tables.
- 033 moves Voucher Engine Admin allocation, unissued revocation, and Version retirement into atomic database RPCs. Allocation creation/increase is serialized per Partner+Version; revocation locks the Allocation row before counting issued vouchers; retirement uses the same Version advisory lock domain as issuance from 026.
- 034 adds canonical `operational_identity_realms` registry keyed by Auth UID, serializing live Admin/Partner/Staff realm ownership and removing the obsolete full Partner user uniqueness constraint while retaining one-live-membership uniqueness.
- 035 adds `staff_operational_context()` so Staff UI receives only its authenticated operational identity and allowed active branch choices without reopening direct reads of `staff_users` or `branches`.
- 036 establishes canonical Partner-wide quota semantics: `voucher_limit=0` means unlimited; positive limits are enforced from canonical `count(vouchers)` at the Voucher INSERT boundary under a Partner row lock. It also fixes Admin setter and Partner dashboard unlimited semantics.
- 037 normalizes Admin and Partner summary buckets to one mutually exclusive status precedence: revoked > expired > redeemed > active.

## Deployment gates
Do not bind frontend URLs/keys until all of the following are true:
1. Exact target Supabase project ID verified.
2. Target confirmed blank/new and not legacy production or XiaoE AI Core.
3. `docs/RUNTIME_DEPLOYMENT_PREFLIGHT_V1.md` target gate passes.
4. Migrations complete without error in numeric order.
5. `supabase/tests/001_contract_smoke_checks.sql` passes.
6. `supabase/tests/002_security_boundary_audit.sql` passes.
7. `supabase/tests/003_partner_isolation_constraints.sql` passes.
8. `supabase/tests/004_admin_mutation_contract.sql` passes.
9. `supabase/tests/005_admin_control_directory_contract.sql` passes.
10. `supabase/tests/006_partner_catalog_contract.sql` passes.
11. `supabase/tests/007_atomic_engine_admin_contract.sql` passes.
12. `supabase/tests/008_partner_issuance_contract.sql` passes.
13. `supabase/tests/009_identity_realm_registry_contract.sql` passes.
14. `supabase/tests/010_staff_operational_contract.sql` passes.
15. `supabase/tests/011_public_voucher_contract.sql` passes.
16. `supabase/tests/012_partner_quota_contract.sql` passes.
17. `supabase/tests/013_reporting_status_precedence_contract.sql` passes.
18. `supabase/tests/014_cutover_readiness_inventory.sql` passes structural review.
19. Test Admin identity exists and resolves as `admin` only.
20. Two independent test Partners exist and cross-Partner reads/writes are rejected.
21. Direct SQL/service-role attempts to pair a Voucher or Redemption with the wrong Partner fail at the declarative FK boundary.
22. Partner browser/user context cannot use the service-role bypass.
23. Admin Edge Function using service-role server context can call 033 mutations only after verifying the original Admin caller.
24. Service-role calls to 033 without a valid active Admin actor_user_id are rejected.
25. One disposable Auth UID cannot be activated concurrently in two different operational realms; exactly one transaction succeeds.
26. After removal/deactivation from one realm, that UID can be activated in another realm.
27. Historical removed Partner membership does not block later Partner re-onboarding, while only one `removed_at IS NULL` Partner membership may exist.
28. Anonymous function inventory contains only `get_public_voucher(uuid)` as the intended business RPC exposure.
29. Staff browser uses `staff_operational_context()`, `verify_voucher()`, `redeem_voucher()`, `staff_today_summary()`, and `staff_recent_redemptions()`; it does not directly read sensitive Voucher/Redemption tables.
30. Staff/manager context is bound to assigned active branch; all_branch_manager must explicitly choose an active branch.
31. Staff Verify -> Redeem -> History works at allowed branch and fails at disallowed branch.
32. Suspended/removed Staff cannot use Staff operational RPCs.
33. Public Voucher lookup uses only `get_public_voucher(uuid)` with the random `public_token`; the browser never queries Voucher tables directly.
34. Public Voucher response exposes no customer phone, Auth/user IDs, allocation IDs, or internal metadata.
35. Random/missing public token fails closed and public lookup never mutates Voucher/Redemption state.
36. Public branch list contains only active branches permitted for that Voucher.
37. Partner catalog returns only Versions the current Partner can actually issue and hides exhausted/inactive/out-of-window entries.
38. Partner issuance uses `issue_engine_voucher()` only; tenant is derived from Auth and the browser never supplies `partner_id`.
39. Partner A cannot issue a Voucher Version allocated only to Partner B.
40. Partner `voucher_limit=0` behaves as unlimited in Admin controls, Partner dashboard, and issuance.
41. Positive Partner voucher limits cannot be exceeded even under concurrent issuance from different valid allocations/versions.
42. Partner quota decisions use canonical Voucher row count, not `partners.vouchers_issued`.
43. Concurrent double redemption does not create two completed uses for a single-use Voucher.
44. Concurrent Voucher Engine issue attempts cannot exceed Allocation or Version supply.
45. Concurrent Admin allocation increases for the same Partner+Version preserve every increment.
46. Revoke-unissued racing with issuance cannot revoke already-issued capacity.
47. Retire Version racing with issue cannot create a Voucher after the Version is inactive.
48. Admin reversal restores usage while preserving the reversed redemption record.
49. Admin and Partner Voucher summary buckets are mutually exclusive using revoked > expired > redeemed > active.
50. Reporting totals reconcile to canonical `vouchers` + `redemptions`.
51. Admin frontend contains no direct business-table read/mutation for control flows; it conforms to `docs/ADMIN_PORTAL_BACKEND_CONTRACT_V1.md` and uses 031 read models for directory data.
52. Partner frontend does not directly read global Voucher Engine tables for its issuable catalog; it uses 032.

## Cutover order
1. New Supabase target verified using `docs/RUNTIME_DEPLOYMENT_PREFLIGHT_V1.md`.
2. Apply migrations.
3. Seed branches.
4. Create first Admin Auth user + `admin_users` row.
5. Deploy required Edge Functions with authenticated JWT enforcement.
6. Run all SQL inventory/contract tests through `014_cutover_readiness_inventory.sql`.
7. Create disposable test Partner / Staff identities.
8. Run end-to-end flow: Allocate -> Partner Catalog -> Issue -> Public -> Staff Verify -> Staff Redeem -> Report -> Reverse -> Report.
9. Run concurrency and cross-tenant runtime proofs.
10. Only then update frontend environment configuration to the new Supabase URL/publishable key and set `enabled:true`.
11. Keep legacy project untouched for rollback/reference until new environment is stable.

## Known transitional compatibility fields
- `partners.vouchers_issued` remains for old frontend compatibility only. It is not authoritative.
- Canonical issuance truth is `count(vouchers)` scoped by `partner_id`.
- Canonical Partner quota rule is `voucher_limit=0` means unlimited; positive values are Partner-wide ceilings.
- Legacy RM60 entrypoint remains temporarily but routes to the Voucher Engine.
- Legacy `customer_ic` parameter is accepted only by compatibility RPC and is ignored/not stored.
- Staff sensitive operational reads stay behind scoped RPCs; the rebuilt Staff frontend must not restore direct table history reads.
- Historical Admin direct mutations of Partner status and voucher limit must stay replaced by the trusted Admin RPC/Edge Function contract.
- Admin Partner/branch control-directory reads must use `admin_partner_directory()` / `admin_active_branches()`, not direct browser table reads.
- Partner issuable Voucher discovery must use `partner_issuable_voucher_catalog()`, not direct browser reads of Voucher Engine tables.
- Partner Voucher issuance must call `issue_engine_voucher(version_id, customer_name, customer_phone)`; Partner identity is never accepted from the browser.
- Voucher Engine Edge Function may read server-side Admin orchestration data, but allocation/revocation/retirement mutations must go through 033 atomic RPCs.
- `partner_users` historical removed memberships are allowed after 034; the canonical live-membership uniqueness rule is the partial `uq_partner_users_live_user` index.
- Customer share links use `voucher.html?v=<public_token>`; `public_token` is separate from the QR `voucher_code`.

## Non-negotiable invariants
- Partner tenants are isolated.
- Partner ownership is enforced both by authorization logic and declarative database constraints.
- Admin is the only cross-Partner operational realm.
- One live Auth identity belongs to exactly one operational realm, enforced by the 034 registry primary key plus realm-maintenance triggers.
- Published Voucher Versions are immutable.
- QR payload is `voucher_code`; public share token is separate.
- Public customer lookup is read-only, token-scoped, minimum-field, and served only through `get_public_voucher(uuid)`.
- Partner-wide quota is enforced at Voucher INSERT; `voucher_limit=0` means unlimited and positive limits use canonical Voucher count.
- Redeem is atomic and server-controlled.
- Reversal preserves history.
- Voucher status reporting uses one precedence: revoked > expired > redeemed > active.
- Voucher Engine issuance lock order is Version serialization first, Allocation row lock second.
- Voucher Engine Admin allocation/revocation/retirement mutations are atomic database operations; Edge code must not perform read-modify-write quota updates.
- Function EXECUTE is default-deny; RPC exposure is explicit.
- Staff sensitive reads use scoped RPCs, not broad direct table SELECT.
- Staff branch context is server-derived; only all_branch_manager chooses among active branches returned by 035.
- Admin browser control reads use scoped Admin RPC read models; Admin browser mutations use authenticated RPC/Edge Function boundaries.
- Partner browser sees an issuance catalog only through tenant-derived RPC scope; it never receives a global Voucher Engine catalog.
- Partner issuance never accepts browser-supplied tenant identity; tenant comes from Auth membership.
- `service_role` is trusted server context only and must never appear in browser code.
- Browser code never contains service_role credentials.