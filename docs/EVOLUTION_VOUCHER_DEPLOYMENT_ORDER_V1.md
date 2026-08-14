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
19. `019_partner_write_guards.sql`
20. `020_scoped_reporting_rpc.sql`
21. `021_identity_realm_exclusivity.sql`
22. `022_partner_claim_response_compatibility.sql`
23. `023_reversal_authorization_v2.sql`
24. `024_engine_concurrency_hardening.sql`
25. `025_authoritative_partner_quota.sql`
26. `026_engine_lock_order_hardening.sql`

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
- 026 deliberately overrides the 024 capacity guard to use Version advisory locking before Allocation row locking and re-check Version active status at the insert boundary. This removes the known Version/Allocation lock-order cycle while preserving race-safe supply enforcement.

## Deployment gates
Do not bind frontend URLs/keys until all of the following are true:
1. Exact target Supabase project ID verified.
2. Target confirmed blank/new and not legacy production.
3. Migrations complete without error in numeric order.
4. `supabase/tests/001_contract_smoke_checks.sql` passes.
5. Test Admin identity exists and resolves as `admin` only.
6. Two independent test Partners exist and cross-Partner reads/writes are rejected.
7. Staff Verify -> Redeem -> History works at allowed branch and fails at disallowed branch.
8. Public voucher page returns only customer-facing fields via public token.
9. Concurrent double redemption does not create two completed uses for a single-use Voucher.
10. Concurrent Voucher Engine issue attempts cannot exceed Allocation or Version supply.
11. Retire Version racing with issue cannot create a Voucher after the Version is inactive.
12. Admin reversal restores usage while preserving the reversed redemption record.
13. Reporting totals reconcile to canonical `vouchers` + `redemptions`.

## Cutover order
1. New Supabase target verified.
2. Apply migrations.
3. Seed branches.
4. Create first Admin Auth user + `admin_users` row.
5. Deploy required Edge Functions with authenticated JWT enforcement.
6. Run smoke/integration tests.
7. Create disposable test Partner / Staff identities.
8. Run end-to-end flow: Allocate -> Issue -> Public -> Verify -> Redeem -> Report -> Reverse -> Report.
9. Only then update frontend environment configuration to the new Supabase URL/publishable key.
10. Keep legacy project untouched for rollback/reference until new environment is stable.

## Known transitional compatibility fields
- `partners.vouchers_issued` remains for old frontend compatibility only. It is not authoritative.
- Canonical issuance truth is `count(vouchers)` scoped by `partner_id`.
- Legacy RM60 entrypoint remains temporarily but routes to the Voucher Engine.
- Legacy `customer_ic` parameter is accepted only by compatibility RPC and is ignored/not stored.

## Non-negotiable invariants
- Partner tenants are isolated.
- Admin is the only cross-Partner operational realm.
- One live Auth identity belongs to exactly one operational realm.
- Published Voucher Versions are immutable.
- QR payload is `voucher_code`; public share token is separate.
- Redeem is atomic and server-controlled.
- Reversal preserves history.
- Voucher Engine issuance lock order is Version serialization first, Allocation row lock second.
- Browser code never contains service_role credentials.
