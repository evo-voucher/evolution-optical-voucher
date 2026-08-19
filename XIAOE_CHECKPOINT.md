# XiaoE Checkpoint

Version: 2.0 Structured Checkpoint
Timestamp: 2026-08-19 16:24 +08:00
Mode: Work mode active
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
- Keep the current Production Voucher system stable while improving XiaoE's ability to continue work reliably across ChatGPT sessions.
- No Voucher feature change is currently open in this checkpoint.

## Current Protocol State
- General reasoning authority: `evo-voucher/xiaoe-core-v2/core/behavior/XIAOE_BEHAVIOR_LOGIC_V1.md`.
- Voucher execution protocol: `XIAOE_CORE.md` version 2.2.
- Current startup order: `Behavior Logic -> Voucher Core -> Checkpoint`.
- Behavior Logic now includes context anchoring, scoped search discipline, owner-first search, competing-path checks, change budget, invariant protection, and risk-sensitive stop/reassess behavior.
- Voucher Core v2.2 includes Voucher Domain Invariants and Business Number Ownership.

## Verified Facts
- Current Production baseline is the Evolution Optical Voucher System on GitHub Pages + Supabase.
- Admin launcher routing fix is merged to main so Admin enters through `admin-dashboard.html`.
- Partner and Staff permanent entry URLs remain `partner-launch.html` and `staff-launch.html` for refresh/cache-safe upgrades.
- Existing voucher redemption branch scope is snapshotted and immutable after issue.
- The current 7-branch redemption path remains a protected stable core unless evidence proves a required change belongs there.
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
PASS: Repository contains the stable canonical voucher, partner isolation, branch-scope snapshot, and reporting layers.
PASS: Behavior Logic is the highest XiaoE engineering-governance layer.
PASS: `XIAOE_CORE.md` version 2.2 is the Voucher-specific execution protocol.
PASS: Voucher Core now protects Domain Invariants and canonical Business Number Ownership.
PASS: Checkpoint responsibility is limited to current project state and continuation context.

## Re-verify Needed Before Next Mutation
Re-verify only what is relevant to the next opened issue or feature, including as applicable:
- current GitHub source / branch state,
- deployed frontend/runtime version,
- Supabase schema / RPC / RLS state,
- active business owner/source of truth,
- affected stable paths and invariants.

Do not re-verify unrelated stable areas without evidence that they are involved.

## Deferred / Not Deployed
- Future multi-merchant voucher network support remains deferred unless explicitly reopened.
- Previously discussed directions include Evolution ↔ Partner, Partner ↔ Partner, and Partner self-redeem.
- Previous preferred direction was an additive Network Layer with Issuer / Voucher Owner / Redeemer / Permission rather than rewriting existing Production voucher semantics.
- Deferred design must not be treated as deployed fact.

## Open Issues / Blockers
- No active Voucher defect or feature is recorded in this checkpoint.
- No known blocker is currently recorded.

## Last Change
- XiaoE engineering governance was strengthened without changing Voucher Production functionality.
- `XIAOE_BEHAVIOR_LOGIC_V1.md` received context-governance and search-discipline enhancements.
- `XIAOE_CORE.md` was upgraded to v2.2 with Voucher Domain Invariants, Business Number Ownership, and a compact startup/continuation flow.
- This checkpoint was converted to Structured Checkpoint v2 for faster and more reliable ChatGPT continuation.

## Next Action
When the next Voucher issue or feature is opened:
1. Load Behavior Logic.
2. Load Voucher Core v2.2.
3. Restore this checkpoint.
4. Re-verify only the state that could affect the new task.
5. Lock the active objective, owner, scope, protected invariants, and verification target.
6. Continue from the smallest justified next action.

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
