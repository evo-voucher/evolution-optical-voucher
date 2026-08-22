# Real Production Backup Execution Checklist

Status: PREPARED / NOT YET EXECUTED

This checklist must be completed before the first real Evolution Voucher production logical backup.

## Safety boundary

- Do not generate live backup files inside the Git repository working tree.
- Use an external local directory such as Desktop, Downloads, or an encrypted removable/private storage location.
- Do not commit, push, attach, or upload live `roles.sql`, `schema.sql`, or `data.sql` to the public repository.
- Do not store database passwords, connection strings, service-role keys, JWT secrets, or encryption passwords in the repository.
- Do not send unencrypted live backup files through WhatsApp or email.

## Approved backup format

Create three Supabase CLI logical dump files:

1. `roles.sql`
2. `schema.sql`
3. `data.sql`

Recommended commands (run locally, with the production database connection string supplied only via the local shell/session):

```sh
supabase db dump --db-url "$SUPABASE_DB_URL" -f roles.sql --role-only
supabase db dump --db-url "$SUPABASE_DB_URL" -f schema.sql
supabase db dump --db-url "$SUPABASE_DB_URL" -f data.sql --use-copy --data-only
```

Do not paste `$SUPABASE_DB_URL` into source files or GitHub.

## Package contents

The final encrypted backup package should contain:

- `roles.sql`
- `schema.sql`
- `data.sql`
- `BACKUP-MANIFEST.txt`

The manifest should record:

- project name
- project ref
- backup timestamp
- backup method
- GitHub `main` commit SHA at backup time
- whether Storage objects were separately backed up
- whether restore drill has been completed

## Encryption

Before transferring to a phone or cloud storage, encrypt the package with a strong password using a ZIP/7z tool that supports encryption.

Do not store the encryption password in the same folder/package as the backup.

## Storage locations

Preferred minimum:

- Copy A: iPhone Files / iCloud Drive or On My iPhone
- Copy B: separate computer/private cloud/encrypted external drive

Do not use the public GitHub repository as live backup storage.

## Verification after dump

Before considering the backup valid:

- confirm all three SQL files exist and are non-empty
- record file sizes
- calculate checksums if practical
- inspect only headers/metadata, not customer records, to confirm the files are readable
- confirm package encryption works
- copy the encrypted archive to the chosen off-site location

## Restore drill rule

Do not restore the first real backup into production for testing.

Restore only into a disposable/test target first, then verify:

- schema objects
- Auth users
- partners
- branches
- vouchers
- allocations
- redemptions
- audit history
- critical RPCs
- Edge Functions deployed separately from GitHub

Then run the critical application chain:

`Allocate -> Issue -> Verify -> Redeem -> Reverse`

## Current status

- Production live dump: NOT EXECUTED
- Off-site phone dry run: PASSED
- Real encrypted backup: NOT CREATED
- Restore drill: NOT EXECUTED
