# Stage / Production Function Lineage Closeout

Status date: 2026-09-02

## Purpose

Document the verified relationship between `voucher-stage` and the EVO Voucher hosted Production function surface after the Stage convergence work. This prevents future maintainers from treating every text/hash difference as a defect.

## Current inventory

- `voucher-stage` public functions: **123**
- hosted Production public functions: **121**
- Count difference is explained by intentional environment-specific signatures listed below.

## Environment-specific signatures

### Stage-only

1. `delete_my_test_voucher(text)`
   - retained as restricted rollback/recovery test tooling
   - not part of the normal authenticated application surface
   - service-role-only on Stage

2. `service_provision_partner(uuid,uuid,text,text,text,text,integer,integer,text)`
   - service-role-only adapter around canonical partner provisioning
   - retained pending a broader hosted/canonical adapter retirement decision

3. `service_set_admin_bootstrap_code(text)`
   - part of the canonical first-Admin bootstrap lineage
   - service-role-only

### Production-only

1. `rls_auto_enable()`
   - environment-level event-trigger helper attached to Production `ensure_rls`
   - not copied to Stage merely for signature parity
   - treat as hosted environment infrastructure unless separately migrated by design

## Sandbox-sensitive guards

`guard_audit_log_immutable()` and `guard_redemption_history()` intentionally do **not** have identical function bodies across environments.

Production still contains legacy sandbox-reset bypass branches that reference the historical `admin_test_sandbox` mechanism. Dedicated Stage keeps the stricter canonical guard behavior and does not copy that Production-only bypass. Their EXECUTE ACLs have nevertheless been converged to `postgres` only.

## Source-shape drift versus behavior drift

A normalized `pg_get_functiondef` hash mismatch is evidence to inspect, not sufficient proof of a behavior difference.

Focused direct-definition comparisons of the following high-risk groups found the same operational logic with source-shape/formatting differences only:

- `assert_partner_tenant(uuid)`
- `guard_admin_identity_realm()`
- `guard_partner_identity_realm()`
- `guard_staff_identity_realm()`
- `resolve_partner_portal_context(uuid)`
- `resolve_staff_portal_context()`
- `staff_operational_context()`
- `reverse_redemption(uuid,text)`
- `admin_engine_allocate(uuid,uuid,integer,text,integer,boolean,text[],uuid,integer,text)`
- `admin_engine_retire_version(uuid,text,uuid)`
- `admin_get_partner_claim_access(uuid)`
- `admin_preview_allocation_effective_branches(uuid,uuid,boolean,text[])`
- `admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid)`
- `admin_provision_staff(uuid,text,uuid,text,text,uuid)`

Do not rewrite Stage solely to make these source hashes identical. Re-open only if a direct semantic comparison, regression test, or runtime symptom shows real behavior drift.

## Converged critical runtime areas

The Stage convergence sequence has already aligned critical voucher/runtime surfaces including allocation integrity, voucher delivery policy, voucher share, redemption/verification runtime, selected Admin definitions, and helper ACLs. Production was kept read-only during this work.

## Decision rule going forward

1. Compare exact signature and ACL set.
2. Compare function attributes (`provolatile`, `prosecdef`, `proconfig`).
3. Inspect direct definitions and dependent schema.
4. Check GitHub migration/history and hosted compatibility intent.
5. Classify as one of:
   - real behavior drift: fix through migration + PR + Stage verification;
   - intentional environment/hosted compatibility difference: document and keep;
   - source-shape-only difference: no runtime mutation.
6. Never mutate Production merely to eliminate text/hash drift.

## Closeout meaning

Function-surface closeout means the Stage database is operationally aligned where parity is required, while documented environment-specific and hosted-compatibility differences remain intentional. It does **not** mean every byte of `pg_get_functiondef` must be identical across environments.
