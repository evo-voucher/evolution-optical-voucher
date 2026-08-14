# Evolution Voucher Core Flow Audit v1

Status: static reconstruction audit. No migration in this report has been applied to legacy production.

## Audited flow
Admin Allocate -> Partner Catalog -> Partner Issue -> Customer Public Voucher -> Staff Verify -> Staff Redeem -> Reporting -> Admin Reverse.

## Verified boundaries
- Admin allocation/revocation/retirement mutations are staged behind atomic database RPCs (033).
- Partner catalog is tenant-derived and scoped by Auth membership (032).
- Partner issuance uses `issue_engine_voucher(uuid,text,text)` and does not accept browser `partner_id`.
- Public customer lookup is anonymous, token-scoped and read-only through `get_public_voucher(uuid)`.
- Staff Verify/Redeem/History are RPC-only; direct sensitive Voucher/Redemption reads remain closed to Staff.
- Redemption locks the Voucher row before usage mutation.
- Partner/Voucher/Redemption tenant identity is backed by declarative constraints from 030.
- Live Auth realm ownership is serialized by the 034 identity registry.
- Admin reversal is Admin-only, requires a reason, preserves the Redemption row, locks the target Redemption and Voucher, and decreases Voucher usage only under a transaction-local reversal authorization marker from 023.

## Quota contradiction found during audit
Older layers disagreed on `partners.voucher_limit = 0`:
1. 001 schema allows issued count above zero when `voucher_limit=0`, which implies a sentinel rather than a zero-capacity ceiling.
2. 013 Admin setter originally treated zero specially (`limit<>0` before comparing to issued count), also implying unlimited.
3. 003 legacy issuer/comment treated zero as zero-capacity and blocked issuance immediately.
4. 025 later Admin setter rejected zero whenever issued vouchers existed.
5. 024 dashboard displayed zero remaining for zero limit.
6. Canonical Engine issuance in 010 did not enforce Partner-wide voucher_limit at all; it enforced allocation/version capacity only.

This was a root-level inconsistency because different issuance paths could interpret the same Partner limit differently.

## Resolution staged in 036
`036_canonical_partner_voucher_quota.sql` establishes one rule:
- `voucher_limit = 0` means unlimited.
- positive `voucher_limit` is a Partner-wide ceiling.
- authoritative issued quantity is `count(public.vouchers)` scoped by Partner.
- the ceiling is enforced by a BEFORE INSERT Voucher trigger, so Engine, compatibility wrappers and future trusted issuance paths share the same boundary.
- the Partner row is locked before the count/decision, making the positive ceiling race-safe across concurrent issuance.
- the Admin setter again allows zero after prior issuance and rejects only positive limits below canonical issued count.
- Partner dashboard reports `voucher_limit_unlimited=true` and `remaining=null` for unlimited rather than misleading `remaining=0`.

Contract checks are staged in `supabase/tests/012_partner_quota_contract.sql`.

## Reporting inconsistency found during audit
The row-level Admin and Partner reports already used an effective status precedence of:

`revoked > expired > redeemed > active`

But the summary counters in 015/020 counted `usage_count >= usage_limit` as redeemed without excluding revoked/expired cases. A revoked fully-used Voucher could therefore appear in both redeemed and revoked summary buckets, producing overlapping totals even though the detailed report showed only one effective status.

## Resolution staged in 037
`037_reporting_status_precedence.sql` overrides Admin and Partner summary functions so their buckets are mutually exclusive and use the same precedence as row-level reporting:
- revoked wins over every other state;
- expired wins over redeemed/active;
- redeemed requires non-revoked, non-expired Voucher at usage limit;
- active requires active, unexpired Voucher below usage limit.

Admin summary now also exposes `vouchers_revoked` explicitly. Contract checks are staged in `supabase/tests/013_reporting_status_precedence_contract.sql`.

## Reversal static review
`023_reversal_authorization_v2.sql` remains structurally consistent with the audited flow:
- only active Admin context can reverse;
- reversal reason is mandatory;
- the original Redemption row is retained and marked `reversed`;
- Voucher usage_count may decrease only while a transaction-local reversal marker names that same Voucher;
- Voucher status is recalculated after reversal, preserving revoked state and respecting expiry;
- audit history records before/after usage and reversal reason.

No new static blocker was identified in this reversal contract. Runtime concurrency and reconciliation tests are still mandatory before cutover.

## Remaining runtime-only proof
The reconstruction is not production-ready until the verified new Supabase target exists and runtime gates prove:
- all migrations apply in numeric order;
- Auth/RLS/EXECUTE boundaries behave under real JWTs;
- two Partners cannot cross tenant boundaries;
- Partner-wide quota, allocation, Version supply and retirement races behave under concurrent sessions;
- Staff allowed/disallowed branch flows behave correctly;
- double redemption remains serialized;
- public-token response is minimum-field in runtime;
- reporting buckets reconcile to canonical Voucher/Redemption rows;
- reversal restores usage without deleting history and reports reconcile before/after reversal.

## Stop gate
Frontend backend configuration remains disabled. Do not bind the reconstructed frontend to any Supabase target until the target is explicitly verified as the new reconstruction environment and all deployment gates pass.
