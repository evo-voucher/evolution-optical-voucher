# Evolution Voucher Deployment Order v1

Status: reconstruction staging only. Do not apply to legacy production project `hukihbcyyqhanaqrizvm`.

## Source of truth
- Code and migration order: this repository.
- Business transactions after deployment: target Voucher Supabase project.
- XiaoE durable project conclusions: XiaoE AI Core `public.memories`.

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
- 025 overrides Admin Partner voucher-limit logic so authoritative issued count is derived from `vouchers`.
- 026 deliberately overrides the 024 capacity guard to use Version advisory locking before Allocation row locking and re-check Version active status at the insert boundary.
- 027 resolves the trusted-server interaction with 019: Partner/browser requests remain tenant-bound, while verified `service_role` server requests may perform cross-Partner Admin operations after caller authorization in the Edge Function. It does not weaken data-consistency guards.
- 028 removes PostgreSQL's default PUBLIC function EXECUTE exposure, preserves explicit authenticated/service_role grants, and re-allows anon only for `get_public_voucher(uuid)`.
- 029 removes Staff direct SELECT paths to Voucher/Redemption/branch-mapping detail. Staff operational reads are served through scoped RPCs from 004/005/020; Admin and owning Partner direct read scopes remain.

## Deployment gates
Do not bind frontend URLs/keys until all of the following are true:
1. Exact target Supabase project ID verified.
2. Target confirmed blank/new and not legacy production.
3. Migrations complete without error in numeric order.
4. `supabase/tests/001_contract_smoke_checks.sql` passes.
5. `supabase/tests/002_security_boundary_audit.sql` passes.
6. Test Admin identity exists and resolves as `admin` only.
7. Two independent test Partners exist and cross-Partner reads/writes are rejected.
8. Partner browser/user context cannot use the service-role bypass.
9. Admin Edge Function using service-role server context can allocate to a selected Partner after verifying the Admin caller.
10. Anonymous function inventory contains only `get_public_voucher(uuid)`.
11. Staff direct SELECT on `vouchers`, `redemptions`, and `voucher_branches` returns no sensitive operational rows outside RPCs.
12. Staff Verify -> Redeem -> History works at allowed branch and fails at disallowed branch.
13. Public voucher page returns only customer-facing fields via public token.
14. Concurrent double redemption does not create two completed uses for a single-use Voucher.
15. Concurrent Voucher Engine issue attempts cannot exceed Allocation or Version supply.
16. Retire Version racing with issue cannot create a Voucher after the Version is inactive.
17. Admin reversal restores usage while preserving the reversed redemption record.
18. Reporting totals reconcile to canonical `vouchers` + `redemptions`.

## Cutover order
1. New Supabase target verified.
2. Apply migrations.
3. Seed branches.
4. Create first Admin Auth user + `admin_users` row.
5. Deploy required Edge Functions with authenticated JWT enforcement.
6. Run smoke/security/integration tests.
7. Create disposable test Partner / Staff identities.
8. Run end-to-end flow: Allocate -> Issue -> Public -> Verify -> Redeem -> Report -> Reverse -> Report.
9. Only then update frontend environment configuration to the new Supabase URL/publishable key.
10. Keep legacy project untouched for rollback/reference until new environment is stable.

## Known transitional compatibility fields
- `partners.vouchers_issued` remains for old frontend compatibility only. It is not authoritative.
- Canonical issuance truth is `count(vouchers)` scoped by `partner_id`.
- Legacy RM60 entrypoint remains temporarily but routes to the Voucher Engine.
- Legacy `customer_ic` parameter is accepted only by compatibility RPC and is ignored/not stored.
- Historical Staff frontend direct-table history reads must be replaced by `staff_recent_redemptions()` before new-backend cutover.

## Non-negotiable invariants
- Partner tenants are isolated.
- Admin is the only cross-Partner operational realm.
- One live Auth identity belongs to exactly one operational realm.
- Published Voucher Versions are immutable.
- QR payload is `voucher_code`; public share token is separate.
- Redeem is atomic and server-controlled.
- Reversal preserves history.
- Voucher Engine issuance lock order is Version serialization first, Allocation row lock second.
- Function EXECUTE is default-deny; RPC exposure is explicit.
- Staff sensitive reads use scoped RPCs, not broad direct table SELECT.
- `service_role` is trusted server context only and must never appear in browser code.
- Browser code never contains service_role credentials.
