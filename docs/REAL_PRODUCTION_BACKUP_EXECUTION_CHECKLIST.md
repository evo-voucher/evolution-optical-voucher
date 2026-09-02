# Real Production Backup Execution Checklist

Status: PREPARED / NOT YET EXECUTED

This checklist must be completed before the first real Evolution Voucher production logical backup.

## Safety Boundary

- Do not generate live backup files inside the Git repository working tree.
- Use an external local directory or approved encrypted/private storage location.
- Do not commit, push, attach, or upload live database dumps to the public repository.
- Do not store database passwords, connection strings, service-role keys, JWT secrets, tokens, or encryption passwords in the repository.
- Do not send unencrypted live backup files through chat or email.

## Approved Backup Package

The final encrypted backup package should contain the logical database export and a `BACKUP-MANIFEST.txt`.

The manifest should record:

- project name
- project ref
- backup timestamp
- backup method
- GitHub `main` commit SHA at backup time
- whether Storage objects were separately backed up
- whether restore drill has been completed

## Encryption

Encrypt the package before transferring it to phone, cloud storage, or removable media.

Do not store the encryption password in the same folder/package as the backup.

## Storage Locations

Keep at least two independent private copies when the backup becomes business-critical. Do not use the public GitHub repository as live backup storage.

## Verification After Dump

Before considering the backup valid:

- confirm all expected dump files exist and are non-empty
- record file sizes
- calculate checksums
- inspect only enough metadata to confirm the files are readable
- confirm package encryption works
- copy the encrypted archive to the chosen off-site location

## Restore Drill Rule

Do not restore the first real backup into Production for testing.

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

## Current Status

- Production live dump: NOT VERIFIED HERE
- Real encrypted backup: NOT VERIFIED HERE
- Restore drill: NOT VERIFIED HERE

This checklist is intentionally conservative: no backup or restore should be considered proven until the actual files and isolated restore have been verified.
