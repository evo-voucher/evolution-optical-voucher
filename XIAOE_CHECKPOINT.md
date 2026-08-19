# XiaoE Checkpoint

Version: 2.0 Structured Checkpoint
Timestamp: 2026-08-19 18:13 +08:00
Mode: Work mode ended
Repository: evo-voucher/evolution-optical-voucher
Branch: main

## Purpose
This file is the compact continuation state for Evolution Voucher.
It records verified project state, the active objective, protected paths, unresolved work, and the next logical action.
It does not define XiaoE reasoning rules or project engineering policy.

Authority order:
`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> XIAOE_CHECKPOINT.md`

Checkpoint content is continuation context, not live truth. Any state that may have changed must be re-verified before mutation.

## Active Goal
- No active Voucher defect or feature is open at session close.
- Preserve the current healthy Production Voucher baseline.
- Security hardening remains optional follow-up work and is not an active Production change.

## Current Protocol State
- General reasoning authority: `evo-voucher/xiaoe-core-v2/core/behavior/XIAOE_BEHAVIOR_LOGIC_V1.md`.
- Voucher execution protocol: `XIAOE_CORE.md` version 2.2.
- Current startup order: `Behavior Logic -> Voucher Core -> Checkpoint`.
- Behavior Logic includes context anchoring, scoped search discipline, owner-first search, competing-path checks, change budget, invariant protection, and risk-sensitive stop/reassess behavior.
- Voucher Core v2.2 includes Voucher Domain Invariants and Business Number Ownership.

## Verified Facts
- Current Production baseline is the Evolution Optical Voucher System on GitHub Pages + Supabase.
- Admin launcher routing fix is merged to main so Admin enters through `admin-dashboard.html`.
- Partner and Staff permanent entry URLs remain `partner-launch.html` and `staff-launch.html` for refresh/cache-safe upgrades.
- Existing voucher redemption branch scope is snapshotted and immutable after issue.
- The current 7-branch redemption path remains a protected stable core unless evidence proves a required change belongs there.
- Read-only health check on 2026-08-19 found 2 partners, 1 voucher, 1 completed redemption, and 7 active branches.
- Health check found 0 orphan redemptions, 0 overused vouchers, 0 negative usage, 0 redeemed-status mismatch, and 0 active vouchers already expired by date.
- Key authorization paths sampled from live Supabase functions showed explicit Admin / Partner / Staff context checks in `admin_dashboard_summary`, `admin_engine_allocate`, `resolve_partner_portal_context`, `resolve_staff_portal_context`, `verify_voucher`, `redeem_voucher`, and `reverse_redemption`.
- Supabase security advisor still reports hardening warnings, including exposed `SECURITY DEFINER` executability and leaked-password protection disabled; these warnings were not treated as active defects without path-specific evidence.
- XiaoE governance is layered as `Behavior Logic -> Voucher Core -> Checkpoint`.

## Protected Paths / Invariants
Unless current evidence proves otherwise, preserve:
- Admin login and launcher flow.
- Partner login and tenant isolation.
- Staff access boundaries.
- Voucher issuance / distribution integrity.
- Redemption correctness and non-duplication according to the authoritative business rule.
- Historical branch-scope snapshot behavior for issued vouchers.
- Reporting and business totals reconciling to authoritative source records.
- Production asset delivery paths already verified as working.

## Last Verified Point
PASS: Core voucher/redemption data integrity checks passed on live Supabase.
PASS: No orphan redemption, overuse, negative usage, status mismatch, or expired-active anomaly was found in the current live dataset.
PASS: Sampled key Admin / Partner / Staff RPC paths contain explicit authorization/context gates.
PASS: Current 7-branch redemption baseline remains protected.
PASS: No Voucher Production code, data, permissions, schema, or configuration was modified during this health-check session.

## Re-verify Needed Before Next Mutation
Re-verify only what is relevant to the next opened issue or feature, including as applicable:
- current GitHub source / branch state,
- deployed frontend/runtime version,
- Supabase schema / RPC / RLS state,
- active business owner/source of truth,
- affected stable paths and invariants.

If security hardening is reopened, classify advisor warnings first and verify intended callers before changing EXECUTE grants or function security behavior.
Do not re-verify unrelated stable areas without evidence that they are involved.

## Deferred / Not Deployed
- Future multi-merchant voucher network support remains deferred unless explicitly reopened.
- Previously discussed directions include Evolution ↔ Partner, Partner ↔ Partner, and Partner self-redeem.
- Previous preferred direction was an additive Network Layer with Issuer / Voucher Owner / Redeemer / Permission rather than rewriting existing Production voucher semantics.
- Optional security hardening remains deferred: review low-risk EXECUTE exposure such as `assign_partner_code_before_insert()` / `admin_next_partner_code()` and consider enabling Supabase leaked-password protection after targeted verification.
- Deferred design or hardening must not be treated as deployed fact.

## Open Issues / Blockers
- No active Voucher defect or feature is recorded at session close.
- No known blocker is currently recorded.
- Security advisor warnings remain informational/deferred until deliberately reopened as a hardening task.

## Last Change
- Performed a read-only Voucher health check against current GitHub/Supabase state.
- Verified current live voucher/redemption integrity and sampled key authorization paths.
- No Production mutation was made.
- Work session closed cleanly at 2026-08-19 18:13 +08:00.

## Next Action
On the next 「小E上线」:
1. Load Behavior Logic.
2. Load Voucher Core v2.2.
3. Restore this checkpoint.
4. Re-verify only the state that could affect the newly opened task.
5. Lock the active objective, owner, scope, protected invariants, and verification target.
6. Continue from the smallest justified next action.

If the next task is security hardening, begin with read-only classification of advisor warnings and protect the current Production business paths until a specific change is proven necessary.

## Checkpoint Update Rule
At 「小E收工」, update only:
- Active Goal,
- Verified Facts that materially changed,
- Protected Paths / Invariants if their verified status changed,
- Last Verified Point,
- Re-verify Needed,
- Open Issues / Blockers,
- Last Change,
- Next Action.

Do not copy chat transcripts, temporary guesses, debugging noise, or general Behavior/Core rules into this file.
