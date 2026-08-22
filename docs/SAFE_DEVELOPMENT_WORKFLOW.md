# Safe Development Workflow

This repository currently operates without a dedicated Supabase development environment. Until one is created, all changes must follow this production-safe workflow.

## Branch Rules

- `main` is Production source of truth.
- Never develop a new feature directly on `main`.
- Create a feature branch from the latest `main` for every change.
- Use clear names such as:
  - `feature/pdf-export`
  - `feature/qr-claim`
  - `fix/redeem-validation`
  - `hardening/rpc-access`
- Merge to `main` only after verification and regression checks pass.

## Database Rules

- All schema or function changes must be migration-first.
- Do not make ad-hoc production schema changes.
- Before applying a migration:
  1. Read current live definition.
  2. Check dependencies.
  3. Assess blast radius.
  4. Define rollback or recovery path.
  5. Use the smallest correct change.
- Prefer transaction-based tests with rollback when production infrastructure must be used.

## Production Sandbox Rules

- Use dedicated test identities and test records only.
- Never use real customer data for experiments.
- Existing test identities may be reused when appropriate.
- Test data must be clearly identifiable and removable without affecting production records.

## Change Gate

Every production change must pass:

`Read -> Impact Check -> Smallest Correct Change -> Verify -> Regression -> Checkpoint`

For high-impact changes, require:

- explicit approval
- dependency review
- rollback plan
- post-deploy regression

## Verification

After every production change verify the affected path and the critical chain where relevant:

`Allocate -> Issue -> Verify -> Redeem -> Reverse`

Also confirm role boundaries remain intact:

- Admin
- Partner Admin
- Partner Staff
- Evolution Staff / Branch Staff
- Public voucher access

## Current Constraint

A dedicated Supabase Development Branch is not currently in use. This workflow reduces risk but does not replace full environment isolation. Large schema rewrites, Auth redesigns, bulk destructive changes, or high-risk infrastructure changes should wait for an isolated development/staging environment where practical.
