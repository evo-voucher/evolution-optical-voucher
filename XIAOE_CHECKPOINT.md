# XiaoE Checkpoint

Timestamp: 2026-08-19 15:59 +08:00
Mode: Work mode active
Repository: evo-voucher/evolution-optical-voucher
Branch: main

## Purpose
This file records only the current verified Evolution Voucher project state, continuation point, deferred work, and unresolved items.
It does not define XiaoE reasoning rules or project engineering policy.

Authority order is defined outside this file:
`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> XIAOE_CHECKPOINT.md`

## Current Engineering State
- Current Voucher project protocol is `XIAOE_CORE.md` version 2.1.
- General XiaoE reasoning is governed by `evo-voucher/xiaoe-core-v2/core/behavior/XIAOE_BEHAVIOR_LOGIC_V1.md`.
- Current production baseline is the Evolution Optical Voucher System on GitHub Pages + Supabase.
- Admin launcher routing fix is merged to main so Admin enters through `admin-dashboard.html`.
- Production should continue using the verified existing flow unless a new change is explicitly opened and re-verified.
- Partner and Staff permanent entry URLs remain the launch pages (`partner-launch.html`, `staff-launch.html`) for refresh/cache-safe upgrades.
- Existing voucher redemption branch scope is snapshotted and immutable after issue; current 7-branch redemption path remains the protected stable core unless evidence proves a required change belongs there.

## Last Verified Point
PASS: Repository contains the stable canonical voucher, partner isolation, branch-scope snapshot and reporting layers.
PASS: XiaoE governance is now layered as Behavior Logic -> Voucher Core -> Checkpoint.
PASS: `XIAOE_CORE.md` is aligned as the Evolution Voucher project execution protocol rather than a second general reasoning core.

## Deferred Design / Not Deployed
- Future multi-merchant voucher network support remains deferred unless explicitly reopened for implementation.
- Previously discussed directions include:
  - Evolution ↔ Partner
  - Partner ↔ Partner
  - Partner self-redeem
- Previous preferred direction was an additive Network Layer with Issuer / Voucher Owner / Redeemer / Permission rather than rewriting existing production voucher semantics.
- No deferred design item should be treated as deployed fact without current verification.

## Unresolved / Next Logical Action
- Keep production stability as the baseline.
- When a new issue or feature is opened, verify the current runtime / GitHub / Supabase state before relying on this checkpoint.
- Continue using development isolation when practical for new feature work.
- Preserve rollback awareness for Production-changing work.

## Continuation Point
On the next 「小E上线」:
- Behavior Logic governs reasoning first.
- `XIAOE_CORE.md` supplies Evolution Voucher project execution rules.
- This checkpoint supplies only the latest project state and continuation context.
- Any checkpoint statement that conflicts with newer verified runtime facts must be treated as stale and replaced by current evidence.
