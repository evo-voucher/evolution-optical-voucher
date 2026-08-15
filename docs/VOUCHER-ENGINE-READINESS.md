# Evolution Optical Voucher Engine — Readiness Baseline

Status date: 2026-08-15

## Engineering rule

Root before flower. Do not treat a hypothesis, partial step, queued CI job, or UI success message as proof of the end state. A change is VERIFIED only when the relevant runtime path and the full regression workflow close successfully.

## Verified local runtime baseline

The disposable local Supabase CI baseline has verified the following core invariants:

- Auth-derived operational realms for Admin, Partner Admin, Partner Staff, and Evolution Staff.
- Partner identity is derived from Auth / partner_users; the browser cannot supply or override partner_id during Voucher issuance.
- Voucher Template / immutable Version / Partner Allocation / issued Voucher Snapshot separation.
- FROM ISSUE validity with true calendar-month arithmetic.
- FROM ALLOCATION validity with arbitrary positive day counts and rejection of non-positive values.
- Multiple allocation batches use earliest-expiry-first consumption for allocation-anchored stock.
- Issued Voucher validity, Theme, Greeting, Terms, and branch IDs are frozen snapshots.
- Partner claim scope and Voucher Version scope intersect at issuance; Partner/Staff cannot broaden redemption scope.
- An issued all-branches Voucher does not gain branches that are created later.
- Partner WhatsApp sharing uses the frozen issued Voucher snapshot and appends the customer Voucher URL from the configured site base.
- Public customer Voucher rendering exposes the frozen Theme, approved Greeting, optional occasion Greeting, Terms, and snapshotted branch details.
- Public presentation configuration is constrained to safe whitelisted values rather than raw HTML/script/arbitrary CSS execution.
- Admin Voucher Engine UI can create classifications/templates, publish immutable Versions, configure validity/presentation, and allocate stock to Partners.

## Key runtime evidence

- Partner WhatsApp browser E2E: `supabase/tests/browser/006_partner_whatsapp_share_e2e.mjs`
- Admin Voucher Engine browser E2E: `supabase/tests/browser/007_admin_voucher_engine_e2e.mjs`
- Public Voucher presentation browser E2E: `supabase/tests/browser/008_public_voucher_presentation_e2e.mjs`
- Voucher delivery snapshot runtime E2E: `supabase/tests/025_voucher_delivery_runtime_e2e.sql`
- Allocation FEFO / future-branch freeze E2E: `supabase/tests/026_voucher_allocation_fefo_and_branch_freeze_e2e.sql`
- Partner Staff tenant / branch non-broadening E2E: `supabase/tests/027_partner_staff_tenant_branch_non_broadening_e2e.sql`

Latest verified local workflow evidence before this document update:

- Run `31873170653`
- Job `94984779560`
- Conclusion: success

## Approved customer share intro

The default issued Voucher greeting is:

```text
Hi 👋
A little gift for you 🎁✨
Here is your Evolution Optical Voucher.
```

An occasion greeting such as Birthday / Raya / Merdeka / Christmas may be appended by the Version and is frozen at issuance.

## Cutover gate — NOT VERIFIED YET

Local CI success does **not** mean the hosted production cutover is complete.

Before commercial hosted use, all of the following must be explicitly verified against the intended new Voucher Supabase target:

1. Confirm the exact hosted target project ID and environment ownership.
2. Confirm no migration or secret is pointed at the XiaoE AI Core project.
3. Confirm the legacy Evolution production project remains untouched during preparation.
4. Apply migrations to the intended new Voucher target only.
5. Deploy required Edge Functions to that same target.
6. Configure frontend `backend-config.js` with the intended hosted URL, publishable key, project ID, and site base; never expose service-role credentials.
7. Create/verify the Admin identity and branch baseline in the target.
8. Run hosted smoke checks for Admin login, Partner login, Partner Staff issuance, WhatsApp share, public Voucher lookup, Staff verify/redeem, and Admin reporting.
9. Verify RLS / RPC behavior using signed real hosted sessions, not only SQL service-role checks.
10. Verify rollback / recovery procedure before switching any public entry point.

Until those hosted checks pass, the authoritative state remains:

- `hosted_cutover_verified = false`
- legacy production must not be mutated as part of this preparation

## Architecture invariants

- Stable Core owns identity, Voucher state, redemption state, and durable relationships.
- Voucher Version owns customer offer and presentation policy.
- Partner Allocation owns Partner stock and allocation-relative validity clock when used.
- Issued Voucher Snapshot owns immutable customer-facing truth after issuance.
- Browser code does not receive service-role credentials.
- High-impact mutations go through narrow Admin or trusted Edge/RPC boundaries.
- Frontend presentation must not be able to widen authorization or redemption scope.

## Remaining product polish

These are not core-engine blockers but should be closed before a polished commercial release:

- Admin navigation/discoverability for Voucher Engine, Staff provisioning, and Partner password tools.
- Reciprocal Back links and navigation browser assertions.
- Hosted operational runbook after the actual target exists.
- Final user acceptance pass on mobile layouts and wording.

This document records the verified local architecture and the remaining hosted cutover boundary. It must not be used as evidence that hosted production is already live.
