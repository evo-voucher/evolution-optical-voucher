# Manual Logical Backup Dry Run

This document defines the approved manual backup dry-run for the Evolution Voucher production database.

## Purpose

Create a recoverable logical backup of production data without storing database credentials or live SQL dumps in the public GitHub repository.

This document is a procedure only. It does not contain live business data and does not execute a backup by itself.

## Current Production Project

- Supabase project ref: `xfivcfwexcxsyiylgryn`
- Project name: `evo-voucher's Project`
- Region: `ap-southeast-1`

## Backup Set

Use an approved Supabase/Postgres logical dump method from a trusted machine. Keep the database connection string only in the local shell/session or another approved secret store.

Expected package:

```text
voucher-backup-YYYYMMDD-HHMM/
  roles.sql
  schema.sql
  data.sql
  BACKUP-MANIFEST.txt
```

## What the Logical Backup Should Cover

The logical backup should preserve the database roles, schema objects, RLS policies, functions, triggers, business tables and required Auth database records, subject to the capabilities and filters of the backup tool used.

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

## What Must Be Recovered Separately

- Edge Function source: recover from GitHub
- Frontend/source assets: recover from GitHub
- Storage objects: export separately if Storage is used
- Supabase API keys / JWT secrets: regenerate or reconfigure
- Auth provider settings / SMTP / OAuth configuration: document and recreate separately
- Custom domains / DNS: recreate separately
- Third-party credentials: restore from secure secret storage, never from GitHub

## Safety Rules

- Never commit live `roles.sql`, `schema.sql`, or `data.sql` files to the public repository.
- Never store database connection strings or passwords in source control.
- Create the dump only from a trusted local machine or trusted private automation runner.
- Store the finished backup outside Supabase and outside the public repository.
- Encrypt the backup at rest where practical.
- Keep at least two independent copies when the backup becomes business-critical.
- Name every package with an exact timestamp.

## Dry-Run Validation

A backup is not considered valid merely because files were created.

After each backup:

1. Confirm the expected dump files exist and are non-empty where expected.
2. Record file sizes and SHA-256 hashes in `BACKUP-MANIFEST.txt`.
3. Confirm the dump command completed without errors.
4. Verify the dump contains expected schema objects.
5. Verify the data export contains key business tables.
6. Confirm no database password or connection string appears in the package.
7. Store the package in the approved off-site location.

## Restore Order

Restore to a disposable test database first, never directly into Production for the first validation.

Recommended order:

```text
1. Prepare target Postgres / Supabase environment
2. Enable required extensions
3. Restore roles
4. Restore schema
5. Restore data
6. Deploy Edge Functions from GitHub
7. Restore required Auth / SMTP / provider configuration
8. Restore Storage objects if applicable
9. Reconfigure secrets and keys
10. Run verification and regression
```

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

## Backup Frequency

Choose a backup interval based on the maximum acceptable business-data loss. Increase frequency as transaction volume and business criticality increase.

## Status

- Procedure defined: YES
- Live Production dump executed by this document: NO
- Restore drill completed: NOT VERIFIED HERE
- Automated external backup enabled: NOT VERIFIED HERE

Next milestone: perform one controlled manual dump and restore it into a disposable test target to prove recoverability.
