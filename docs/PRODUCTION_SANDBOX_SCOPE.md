# Production Sandbox Scope

This document defines the temporary testing boundary used while the project does not have a dedicated Supabase Development/Staging environment.

## Purpose

Allow controlled verification against production infrastructure without mixing test activity with real business data or changing the production branch topology.

## Approved Sandbox Identities

- Partner: `Test partner`
- Evolution staff: `testmines`

These identities are designated for test-only activity. Do not use real customer identities for sandbox verification.

## Branch Rule

Do **not** create a new active Test Branch in production solely for testing.

Reason: the voucher engine contains `all_branches` scopes. Adding a new active branch could expand the eligible branch set of existing vouchers, allocations, or partner claim scopes and unintentionally change real production behavior.

When branch behavior must be tested, use an existing branch with a designated test staff account and clearly marked test vouchers/customers.

## Test Data Rules

- Prefix or label test customer data clearly with `TEST` where the UI permits.
- Do not use real customer phone numbers, birthdays, or personally identifiable data.
- Do not issue test vouchers to real customers.
- Keep test quantities minimal.
- Where possible, run database verification inside a transaction and `ROLLBACK` after assertions.
- Never delete or rewrite real redemption or audit history to clean up a test.

## Change Gate

Before any production-backed test:

1. Read current production state.
2. Confirm the test uses only designated sandbox identities/data.
3. Check impact on partner, branch, voucher, allocation, redemption and reporting scopes.
4. Prefer read-only or transaction-rollback tests.
5. If a persistent write is required, keep it minimal and reversible.
6. Verify the intended result.
7. Run regression checks on the affected workflow.
8. Record a checkpoint.

## Prohibited Without Dedicated Staging

The following must not be trialed directly against production merely for experimentation:

- Destructive schema redesigns
- Bulk data rewrites or deletes
- Auth model changes
- RLS rewrites with uncertain blast radius
- Core issuance/redemption architecture replacement
- Changes that cannot be cleanly rolled back

## Release Flow

`Feature Branch -> Impact Check -> Migration-first -> Sandbox/Test -> Verify -> Regression -> Approval -> Merge to main -> Production Verify -> Checkpoint`

## Future Replacement

This scope is temporary. Once a dedicated Development/Staging environment is created, feature testing and test data should move there and production-backed sandbox testing should be reduced to final smoke verification only.
