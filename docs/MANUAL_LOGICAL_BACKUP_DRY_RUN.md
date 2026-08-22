# Manual Logical Backup Dry Run

This document defines the approved manual backup dry-run for the Evolution Voucher production database while the Supabase project remains on the Free Plan.

## Purpose

Create a recoverable logical backup of production data without storing database credentials or live SQL dumps in the public GitHub repository.

This document is a procedure only. It does not contain live business data and does not execute a backup by itself.

## Current Production Project

- Supabase project ref: `xfivcfwexcxsyiylgryn`
- Project name: `evo-voucher's Project`
- Region: `ap-southeast-1`
- Plan: Free

## Backup Set

Use Supabase CLI and export the database as three separate files:

```sh
supabase db dump --db-url "[CONNECTION_STRING]" -f roles.sql --role-only
supabase db dump --db-url "[CONNECTION_STRING]" -f schema.sql
supabase db dump --db-url "[CONNECTION_STRING]" -f data.sql --use-copy --data-only
```

Expected package:

```text
voucher-backup-YYYYMMDD-HHMM/
  roles.sql
  schema.sql
  data.sql
  BACKUP-MANIFEST.txt
```

## What the Logical Backup Covers

The database dump is expected to preserve database roles, schema objects, RLS policies, functions, triggers, public business data, and Auth database records such as `auth.users`, subject to Supabase CLI filtering.

Important production tables include:

- partners
- partner_users
- staff_users
- branches
- partner_customers
- voucher_templates
- voucher_versions
- partner_voucher_access
- partner_voucher_allocations
- voucher_allocation_events
- vouchers
- voucher_branches
- redemptions
- admin_audit_log

## What Is Not Covered By This Database Dump

The following must be recovered separately:

- Edge Function source: recover from GitHub
- Frontend/source assets: recover from GitHub
- Storage objects: export separately if Storage is used
- Supabase API keys / JWT secrets: regenerate or reconfigure
- Auth provider settings / SMTP / OAuth configuration: document and recreate separately
- Custom domains / DNS: recreate separately
- Third-party credentials: restore from secure secret storage, never from GitHub

## Safety Rules

- Never commit `roles.sql`, `schema.sql`, or `data.sql` containing live production data to the public repository.
- Never store database connection strings or passwords in source control.
- Create the dump only from a trusted local machine or trusted private automation runner.
- Store the finished backup outside Supabase and outside the public repository.
- Encrypt the backup at rest where practical.
- Keep at least two independent copies if the backup becomes business-critical.
- Name every package with an exact timestamp.

## Dry-Run Validation

A backup is not considered valid merely because files were created.

After each backup:

1. Confirm `roles.sql`, `schema.sql`, and `data.sql` exist and are non-empty where expected.
2. Record file sizes and SHA-256 hashes in `BACKUP-MANIFEST.txt`.
3. Confirm the dump command completed without errors.
4. Verify the dump contains expected public schema objects.
5. Verify `data.sql` contains key business tables.
6. Confirm no database password or connection string appears in the package.
7. Store the package in the approved off-site location.

## Restore Order

Restore to a disposable test database first, never directly into production for the first validation.

Recommended order:

```text
1. Prepare target Postgres / Supabase environment
2. Enable required extensions
3. Restore roles.sql
4. Restore schema.sql
5. Restore data.sql
6. Deploy Edge Functions from GitHub
7. Restore required Auth / SMTP / provider configuration
8. Restore Storage objects if applicable
9. Reconfigure secrets and keys
10. Run verification and regression
```

For a compatible Postgres target, Supabase documents a restore pattern using `psql --single-transaction`, `ON_ERROR_STOP=1`, and loading roles, schema, then data.

## Post-Restore Verification

Minimum verification set:

- Admin login works
- Partner login works
- Staff login works
- Partner and Staff remain tenant/branch isolated
- Voucher templates and versions exist
- Allocations match expected counts
- Voucher row counts match backup manifest
- Redemption history exists
- Audit history exists
- Public voucher lookup works
- Critical chain passes:

```text
Allocate -> Issue -> Verify -> Redeem -> Reverse
```

## Backup Frequency Recommendation

Until a paid automated backup option is adopted:

- Minimum: weekly backup
- Better for active commercial use: daily backup
- Additional backup before any high-impact production migration

The appropriate interval should reflect acceptable data loss. A daily backup implies up to roughly one day of business data could be lost if the latest database copy is unusable.

## Status

- Procedure defined: YES
- Live production dump executed by this document: NO
- Restore drill completed: NO
- Automated external backup enabled: NO

Next milestone: perform one controlled manual dump and restore it into a disposable test target to prove recoverability.
