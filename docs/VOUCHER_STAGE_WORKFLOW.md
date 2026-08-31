# Voucher Stage Workflow

Status: Proposed

## Purpose

Separate development, staging, and production so new Voucher changes can be tested without risking live customer operations.

## Environments

### Production

- Supabase project ref: `xfivcfwexcxsyiylgryn`
- Purpose: live customer, partner, voucher, redemption, and operational data
- Rule: do not use Production as a development sandbox

### Stage

- Supabase project ref: `tagusbcluzoxueixjmwh`
- Project name: `voucher-stage`
- Purpose: schema changes, migrations, Edge Functions, permissions, integration tests, and feature validation
- Rule: use test-only data; do not copy live customer business data by default

### GitHub development

- Start substantive work from `main` on a dedicated development branch
- Prefer branch names such as `feature/...`, `fix/...`, or `chore/...`
- Run local/CI checks before Stage deployment

## Standard promotion path

`development branch -> voucher-stage -> validation -> pull request -> main -> production deployment`

A change must not be promoted to Production merely because it compiles or passes local tests. Stage is the required integration checkpoint for production-impacting changes.

## Data isolation

- Production data stays in Production by default
- Stage uses synthetic/test customers, partners, staff, vouchers, and redemption records
- No automatic Production-to-Stage customer data sync
- No Stage-to-Production data copy except explicitly approved migrations/configuration that are designed for promotion
- Secrets, service-role keys, Supabase URLs, and runtime tokens must remain environment-specific

## Deployment safety

- Treat `main` as the production baseline
- Apply database changes through migrations rather than ad-hoc manual edits when practical
- Validate migrations and Edge Functions on Stage first
- Preserve rollback paths for production-impacting changes
- Do not weaken RLS, authentication, tenant isolation, or security boundaries simply to make Stage tests pass
- Destructive Production operations remain owner-approval actions

## XiaoE operating rule

When the owner requests development or testing of Voucher features without explicitly naming an environment, XiaoE should default to the Stage workflow and must not modify Production directly.

Production changes require an explicit production promotion/deployment instruction, or a clearly identified incident-remediation situation within the granted authority boundary.
