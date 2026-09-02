# Disaster Recovery Runbook

This runbook defines the recovery path for the Evolution Optical Voucher System.

## Recovery Model

The system has two recovery layers:

1. **Source / Schema Recovery**
   - GitHub `main` is the source of truth for application code, Supabase migrations, Edge Functions, tests and recovery documentation.
   - This layer can rebuild application and database structure, but it does not restore current live business records by itself.

2. **Live Business Data Recovery**
   - Live business data requires a separately verified backup outside the public GitHub repository.
   - A source archive is not a substitute for a database backup.

## Protected Production Assets

Critical live data includes:

- Partners and partner users
- Evolution staff users
- Customer records
- Voucher templates and versions
- Voucher access and allocations
- Issued vouchers
- Voucher branch scopes
- Redemptions and reversals
- Allocation event history
- Admin audit history
- Operational identity mappings

## Backup Policy

- Create an external logical database backup on a regular schedule appropriate to the business risk.
- Store backups outside the Supabase project and outside the public GitHub repository.
- Do not commit database dumps, customer data, credentials, service-role keys, database passwords, tokens or secrets to GitHub.
- Encrypt backup files at rest when they contain personal or transactional data.
- Keep at least one copy in a location independent from the production Supabase account.
- Record the backup timestamp, project ref, schema version / Git commit and verification status.

## Recovery Objectives

- RPO should approximately match the verified backup frequency.
- RTO should be validated through a restore drill rather than assumed.

## Incident Recovery Sequence

### 1. Stabilize

- Stop non-essential writes.
- Do not run cleanup, reset, purge or schema-changing operations.
- Preserve logs and evidence.
- Identify the incident start time and last known-good state.

### 2. Classify

Determine whether the incident is:

- Frontend / deployment failure
- Edge Function failure
- Database schema / function failure
- Data corruption / accidental deletion
- Auth / account incident
- Full project loss

### 3. Choose Recovery Source

Use the smallest recovery scope possible:

- Frontend: restore from GitHub `main` / known-good commit.
- Edge Functions: redeploy known-good function source from GitHub.
- Schema / RPC: apply or revert using reviewed migrations / known-good definitions.
- Live data: restore from the latest verified external logical backup.
- Full rebuild: create a clean Supabase project, replay migrations, deploy Edge Functions, restore live data, restore required Auth/configuration, then reconnect the application.

### 4. Restore in Controlled Order

For a full rebuild:

1. Create replacement Supabase project.
2. Confirm region and Postgres compatibility.
3. Apply migrations in repository order.
4. Verify RLS, constraints, triggers, RPC privileges and integrity guards.
5. Restore live business data from the latest verified logical backup.
6. Restore / recreate Auth users and required identity mappings using an approved recovery method.
7. Deploy Edge Functions from GitHub.
8. Restore required secrets and environment configuration from the secure secret store, never from source control.
9. Reconnect frontend only after verification passes.

## Mandatory Post-Restore Verification

Before reopening normal business use, verify:

- Admin login and admin authorization
- Partner Admin isolation
- Partner Staff isolation
- Evolution Staff / branch isolation
- Public voucher lookup
- Allocation rules
- Voucher issuance
- Voucher verification
- Voucher redemption
- Redemption reversal
- Audit trail behavior
- Allocation-event integrity
- No orphan partner/version/allocation/voucher/redemption records

Critical chain:

`Allocate -> Issue -> Verify -> Redeem -> Reverse`

## Restore Drill

A backup is not considered reliable until it has been successfully restored in a non-production environment.

1. Restore the latest logical backup into an isolated environment.
2. Replay / reconcile migrations as required.
3. Deploy Edge Functions.
4. Run the critical-chain regression.
5. Record any missing dependencies or manual recovery steps.
6. Update this runbook.

## Prohibited Recovery Practices

- Do not use the public GitHub repository to store live database dumps.
- Do not use real customer data in a public artifact.
- Do not assume a source-code ZIP contains live business data.
- Do not restore directly over Production without first identifying the incident scope and recovery point.
- Do not delete a Supabase project as a recovery step unless a replacement and verified backup already exist.

## Current Voucher Production Reference

- Voucher Supabase project ref: `xfivcfwexcxsyiylgryn`

This is an operational identifier only. No credentials or secrets belong in this document.

## Status

- Source / schema recovery documentation: **READY**
- Edge Function source recovery documentation: **READY**
- Live-data external logical backup: **MUST BE VERIFIED SEPARATELY**
- Restore drill: **MUST BE VERIFIED SEPARATELY**

Disaster recovery should be treated as proven only after a real backup and isolated restore drill both pass.
