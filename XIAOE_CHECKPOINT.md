# XiaoE Checkpoint

Version: 2.2 Structured Checkpoint
Timestamp: 2026-08-21 09:10 +08:00
Mode: Work mode ended
Repository: evo-voucher/evolution-optical-voucher
Branch: main

## Purpose
Compact continuation state for Evolution Voucher. Re-verify any live/runtime fact before future mutation.

Authority order:
`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> XIAOE_CHECKPOINT.md`

## Active Goal
- No active code change is open at session close.
- Preserve the current Production Voucher baseline.
- Continue using `Capability First -> Gap Type -> Smallest Correct Change`.

## Verified Facts
- Production Supabase project: `xfivcfwexcxsyiylgryn`.
- Archived Partner issue was fixed live: production `admin_partner_directory()` now includes archived Partners while excluding internal ADMIN pseudo-partner.
- Latest Activity is live in Admin V2 and production `admin_latest_activity(integer)` exists.
- Admin V2 shows Latest Activity preview and `View All` history.
- Admin Summary includes `Total Allocated`; mobile layout centers the Total Allocated card.
- Admin entry/login routing was unified to the latest Admin V2 so Main -> Admin and Admin login no longer route to old `admin-b-revoke.html`.
- Admin Notification feature is live in source and production data layer.
- Notification rules: frontend shows up to 30 recent items; notification read-state is temporary and uses a 24-hour expiry; business records are not duplicated into the notification table.
- Production has `admin_notification_reads`, `admin_notifications(integer)`, and `admin_mark_notifications_read()`.
- Production pg_cron cleanup for expired Notification read-state is active on an hourly schedule; expired read-state is hard-deleted. Current verified expired residual count at setup time was 0.
- Notification read state is also used to drive Latest Activity read-dot visual state; current intended visual: unread cyan, read red while the temporary read-state exists.
- Notification JS cache-bust was advanced to `notify2` so mobile clients fetch the newer notification/read-dot logic.
- Partner V2 mobile long-page behavior was improved: Partner Controls expansion no longer leaves the full Create Partner section competing for scroll space.
- Main portal, Admin, Partner, Staff and module-style controls received faster touch feedback using `touch-action: manipulation`, fast active-state transitions and stronger pressed feedback.
- Main portal Refresh received an additional stronger touch-response treatment.

## Current Main Baseline
- Last functional main commit before this checkpoint write: `931ff5c5d6dfc4e5392f47b4a890342e629c8a88`.
- This checkpoint commit will advance `main`; treat the post-checkpoint HEAD as the new source baseline.

## Protected Paths / Invariants
Preserve unless current evidence proves change is required:
- Admin login and launcher flow.
- Partner login and tenant isolation.
- Staff access boundaries.
- Voucher allocation / issuance integrity.
- Redemption correctness and non-duplication.
- Voucher/redemption/audit history.
- Notification must remain a temporary reminder layer, not a second business-record store.
- Latest Activity must remain read-only and derive from authoritative business/audit sources.
- Production / Dev / UAT boundaries.

## Last Verified Point
PASS: Archived Partner visibility fixed live.
PASS: Latest Activity visible in live Admin V2.
PASS: Admin entry routing unified to latest Admin V2.
PASS: Total Allocated mobile presentation centered.
PASS: 24-hour lightweight Notification read-state production layer deployed.
PASS: Expired Notification read-state automatic hard-delete cron active.
PASS: Notification and Latest Activity read-dot linkage source merged.
PASS: Notification JS cache-bust merged.
PASS: touch responsiveness enhancements merged for Main / Admin / Partner / Staff controls.
PASS: Refresh touch responsiveness enhancement merged.

## Re-verify Needed Before Next Mutation
Only re-verify what the next task touches. In particular, if Notification visuals are revisited, verify live mobile behavior first:
- whether Admin V2 is serving `admin-notifications.js?v=20260821-notify2`,
- whether opening Notifications makes the matching Latest Activity read dots turn red,
- whether new Partner issued / Staff redeemed events appear in Notification and Latest Activity as expected,
- whether 24-hour expiry/cron cleanup remains active.

If button responsiveness is revisited, verify actual iPhone runtime feel before changing CSS again; source already contains fast-touch rules.

## Open Issues / Blockers
- No source-code blocker is open at close.
- Latest Activity read-dot red-state was not yet visually re-confirmed by a fresh post-`notify2` screenshot after the final cache-bust merge; re-check runtime before further code changes.
- Notification cron is hourly, so an expired read-state can remain for less than roughly one additional hour before scheduled hard-delete. The attempted tighter frequency was intentionally not forced past platform safety checks.

## Last Change
- Enhanced Main portal Refresh touch response and merged `fix/refresh-touch-response` into main.
- Prior session changes also merged Admin/Partner/Staff touch feedback, Main tile touch feedback, Notification cache-bust, read-dot linkage, Admin routing cleanup, Latest Activity, Notification infrastructure, and archived Partner production fix.
- Work session closed cleanly at 2026-08-21 09:10 +08:00.

## Next Action
On next `小E上线`:
1. Load Behavior Logic.
2. Load Voucher Core.
3. Restore this checkpoint.
4. Read current `main` HEAD.
5. Re-verify only the runtime state relevant to the new issue.
6. Continue from the smallest justified action.

For release-sensitive work:
`DEV proof -> UAT when required -> Production Gate -> deploy -> Production Smoke -> PASS or rollback/recovery`.
