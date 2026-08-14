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

## Quota contradiction found during audit
Three older layers disagreed on `partners.voucher_limit = 0`:
1. 001 schema allows issued count above zero when `voucher_limit=0`, which implies a sentinel rather than a zero-capacity ceiling.
2. 013 Admin setter originally treated zero specially (`limit<>0` before comparing to issued count), also implying unlimited.
3. 003 legacy issuer/comment treated zero as no quota and blocked issuance immediately.
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

## Remaining runtime-only proof
The reconstruction is not production-ready until the verified new Supabase target exists and runtime gates prove:
- all migrations apply in numeric order;
- Auth/RLS/EXECUTE boundaries behave under real JWTs;
- two Partners cannot cross tenant boundaries;
- quota, allocation, Version supply and retirement races behave under concurrent sessions;
- Staff allowed/disallowed branch flows behave correctly;
- double redemption remains serialized;
- public-token response is minimum-field in runtime;
- reporting and reversal reconcile to canonical Voucher/Redemption history.

## Stop gate
Frontend backend configuration remains disabled. Do not bind the reconstructed frontend to any Supabase target until the target is explicitly verified as the new reconstruction environment and all deployment gates pass.