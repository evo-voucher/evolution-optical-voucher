# Evolution Voucher Deployment Order v1

Status: reconstruction staging only. Never apply this chain to legacy production project `hukihbcyyqhanaqrizvm`.

## Source of truth
- Migration/code order: this repository.
- Runtime business truth after cutover: the verified Voucher Supabase target.
- XiaoE durable conclusions: XiaoE AI Core `public.memories`.
- Target/cutover safety: `docs/RUNTIME_DEPLOYMENT_PREFLIGHT_V1.md`.

## Migration order
Apply strictly by numeric filename order:

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
38. `038_atomic_identity_provisioning.sql`
39. `039_partner_staff_server_management.sql`
40. `040_partner_password_reset_audit.sql`
41. `041_serialize_voucher_version_publish.sql`
42. `042_partner_staff_directory.sql`

## Important dependency / ownership checkpoints
- 009 introduces Voucher Engine tables; 010 is the canonical Partner issuance RPC.
- 023 owns controlled reversal semantics and immutable Voucher identity protection.
- 026 owns canonical issuance lock order: Version serialization first, Allocation row lock second.
- 028 makes function execution default-deny; only explicitly granted RPCs may be called.
- 029 keeps sensitive Staff reads behind scoped RPCs.
- 030 adds declarative tenant FKs so trusted server writes cannot cross Partner ownership.
- 033 owns atomic Voucher Engine Admin allocation/revocation/retirement; Edge code authorizes/routes only.
- 034 owns one-live-operational-realm per Auth UID and allows historical removed Partner memberships.
- 035 owns Staff operational/branch context.
- 036 is the canonical Partner quota layer: `voucher_limit=0` means unlimited; positive limits use canonical Voucher count at INSERT under a Partner row lock.
- 037 owns mutually exclusive summary precedence: revoked > expired > redeemed > active.
- 038 keeps broad service-role table DML closed. Partner/Evolution Staff provisioning is performed by narrow server-only SECURITY DEFINER RPCs after the Edge Function verifies the original caller JWT. Auth user creation remains in trusted Edge code; DB profile/business writes are atomic.
- 039 owns Partner Staff create/rename/suspend/activate/remove and password-reset audit boundaries. Partner identity is derived from the active Partner Admin actor; Partner row locking serializes `staff_limit` enforcement.
- 040 owns the database audit row for successful Partner Admin Auth password reset under the original authenticated Admin caller context.
- 041 serializes Voucher Version publishing on the owning Voucher Template row before allocating `version_no`; the existing unique `(template_id,version_no)` remains the declarative last line of defense.
- 042 owns Partner Staff directory reads. Partner scope is derived from `auth.uid()` plus active `partner_admin` membership; there is no caller-supplied `partner_id` input.

## Automated SQL contracts
Before cutover all SQL contracts under `supabase/tests/*.sql` must pass, through:

- `020_voucher_version_publish_concurrency_contract.sql`
- `021_partner_staff_directory_contract.sql`

The full suite remains authoritative; do not selectively skip earlier contracts.

## Free runtime gates
The free GitHub Actions local-Supabase pipeline must pass from a clean rebuild:

1. `supabase start` succeeds.
2. `supabase db reset` applies 001–042 without error.
3. Every SQL contract succeeds with `ON_ERROR_STOP=1`.
4. `supabase/tests/runtime/001_publish_concurrency_e2e.sh` proves two independent-session concurrent publishes on the same Template commit as sequential versions without retry-based recovery.
5. `supabase/tests/http/001_signed_gotrue_core_flow_e2e.sh` passes real GoTrue signup/login -> signed JWT -> PostgREST RPC flow.
6. Local Edge Functions start and unauthenticated protected calls fail closed.
7. `002_edge_function_boundary_e2e.sh` passes create-partner, create-staff, Voucher Engine Admin boundary and Partner denial.
8. `003_partner_staff_edge_lifecycle_e2e.sh` passes Partner Staff create/rename/suspend/activate/password-reset/remove with tenant/realm preservation.
9. `004_admin_edge_controls_e2e.sh` passes Admin staff-limit control and Partner password reset, while Partner JWT is rejected from Admin boundaries.
10. Every browser suite under `supabase/tests/browser/*.mjs` passes. CI must discover all suites automatically rather than hardcoding one filename.
11. Portal HTML and shared frontend JS changes trigger the same runtime smoke workflow.
12. Migration state is read back and local Supabase teardown succeeds.

Latest whole-run verified local baseline:

- Run ID: `31856367830`
- Job ID: `94941786359`
- Result: `completed / success`

This run proved migrations 001–042, SQL contracts through 021, concurrent publish runtime proof, signed GoTrue flow, trusted Edge boundaries, Partner Staff lifecycle, Admin controls, all browser E2E suites, migration state and teardown.

## Browser capability proof currently covered
The browser suite now verifies, in disposable local runtime:

- Partner login and tenant-derived dashboard;
- Partner Staff creation through trusted `manage-partner-staff` boundary;
- canonical Voucher issuance and Public Voucher rendering;
- Staff verify/redeem and visible redemption outcome;
- Admin reporting;
- Admin Partner provisioning through `create-partner` and successful Partner login;
- Admin Evolution Staff provisioning through `create-staff` and successful Staff login;
- Admin Partner password reset through `reset-partner-password`, including old-password rejection and new-password login.

Browser tests sharing the same origin also share Supabase Auth storage. Test design must preserve the intended authoritative actor by safe ordering or isolated browser contexts; a session replacement is a fixture failure unless evidence proves the product permission layer is wrong.

## Security / data gates
Do not bind frontend URL/key until all are true:

- Exact new hosted target ID verified; it is neither legacy production nor XiaoE AI Core.
- Partner A/B cross-tenant reads, writes and allocation use are rejected.
- One Auth UID cannot own two live Admin/Partner/Staff realms.
- Historical removed Partner membership does not block valid later re-onboarding.
- Anonymous business exposure is limited to the intended `get_public_voucher(uuid)` RPC.
- Public Voucher response excludes phone, Auth IDs, allocation IDs and internal metadata.
- Partner issuance derives tenant from Auth and never accepts browser `partner_id`.
- Partner Staff directory derives tenant from Auth and never accepts browser `partner_id`.
- `voucher_limit=0` behaves as unlimited; positive Partner quota cannot be exceeded concurrently.
- Staff Verify is read-only; Redeem is atomic and branch-scoped; double redemption is rejected.
- Successful Staff redemption leaves an explicit visible confirmation before the operator continues; transient form state must not hide the outcome.
- Admin reversal restores usage but preserves the reversed Redemption row.
- Reporting reconciles to canonical Vouchers + Redemptions using revoked > expired > redeemed > active.
- Service-role credentials never appear in browser code.
- Edge Functions authorize the original signed caller in caller JWT context before trusted server operations.
- Service-role business mutations use narrow DB RPCs, not broad direct table DML.

## Cutover order
1. Verify a new hosted Supabase target using `docs/RUNTIME_DEPLOYMENT_PREFLIGHT_V1.md`.
2. Apply 001–042 in order.
3. Confirm the seven branch baseline rows.
4. Create first Admin Auth user + active `admin_users` row.
5. Deploy required Edge Functions with JWT enforcement.
6. Run all SQL contracts, signed HTTP/Edge tests, runtime concurrency proof and every browser E2E suite against disposable identities.
7. Run concurrency/cross-tenant proofs.
8. Only then set `assets/js/backend-config.js` to the new Supabase URL/publishable key and `enabled:true`.
9. Keep legacy production untouched as rollback/reference until the new environment is stable.

## Compatibility notes
- `partners.vouchers_issued` is compatibility-only; canonical issuance truth is `count(vouchers)` by Partner.
- Legacy RM60 entrypoint temporarily routes into the Voucher Engine.
- Legacy `customer_ic` argument is accepted only by compatibility RPC and is not stored.
- Customer share URL uses `voucher.html?v=<public_token>`; QR payload remains `voucher_code`.
- Partner Staff historical removed rows may coexist after 034; only one live membership is allowed.

## Non-negotiable invariants
- Partner tenants are isolated; Admin is the only cross-Partner operational realm.
- One live Auth identity belongs to exactly one operational realm.
- Published Voucher Versions are immutable business snapshots.
- Voucher Version publishing is serialized per Template; version allocation is not best-effort retry logic.
- QR `voucher_code` and customer `public_token` are separate credentials/use cases.
- Partner-wide quota is enforced at Voucher INSERT; 0 means unlimited.
- Voucher Engine Admin and identity/lifecycle mutations are database-owned atomic/scoped operations.
- Partner Staff directory scope is auth-derived and tenant-scoped.
- Redeem is atomic; reversal preserves history.
- Sensitive Staff/Partner/Admin reads and writes stay behind scoped authorization boundaries.
- Function EXECUTE is explicit/default-deny.
- `service_role` is server-only and never a browser credential.
- A failed test is not proof the business invariant is wrong; identify and prove the owning failure layer before changing product logic.
- Intermediate green steps are not equivalent to whole-run success.
