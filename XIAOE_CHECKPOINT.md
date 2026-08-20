# XiaoE Checkpoint

Version: 2.1 Structured Checkpoint
Timestamp: 2026-08-21 02:51 +08:00
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
- Preserve the current verified Production Voucher baseline.
- Archived Partner discoverability/restore flow has been repaired at source level and merged to main.

## Current Protocol State
- General reasoning authority: `evo-voucher/xiaoe-core-v2/core/behavior/XIAOE_BEHAVIOR_LOGIC_V1.md`.
- Voucher execution protocol: `XIAOE_CORE.md` version 2.3.
- Current startup order: `Behavior Logic -> Voucher Core -> Checkpoint`.
- Environment execution companion: `docs/XIAOE-ENVIRONMENT-ROUTING.md`.
- Project environment boundary contract: `docs/ENVIRONMENT-CONTRACT.md`.
- XiaoE Core now includes the durable principle `Capability First -> Gap Type -> Smallest Correct Change` in `evo-voucher/xiaoe-core-v2/core/principles/CAPABILITY_BEFORE_CHANGE_V1.md`.

## Verified Facts
- Current Production frontend target is `xfivcfwexcxsyiylgryn`.
- Production `assets/js/backend-config.js`, current Readiness target, and Production Public Smoke expectations are aligned to `xfivcfwexcxsyiylgryn`.
- Dev/UAT/Production environment governance is established and verified.
- Partner V2 (`experience/partner-v2.html`) already supports rendering `archived` status and status controls.
- The root cause of missing Archived Partners was the Admin read model `admin_partner_directory()` filtering out archived rows.
- A new migration `supabase/migrations/20260821024700_admin_partner_directory_include_archived.sql` was added to return archived Partners to Admin while still excluding the internal `ADMIN` pseudo-partner.
- Archived Partner restore UX label was improved in `assets/js/partner-management-ui.js`: archived state now presents `Restore Partner` while still using the existing safe `active` status transition.
- Main now includes the archived-directory fix at commit `7ec7b2bbd082b88a9af4f9ceb3fdf872530b8570`.
- GitHub merge state for the archived-directory fix was verified identical between `main` and `fix/admin-directory-include-archived`.

## Protected Paths / Invariants
Unless current evidence proves otherwise, preserve:
- Admin login and launcher flow.
- Partner login and tenant isolation.
- Staff access boundaries.
- Voucher issuance / distribution integrity.
- Redemption correctness and non-duplication according to the authoritative business rule.
- Historical branch-scope snapshot behavior for issued vouchers.
- Reporting and business totals reconciling to authoritative source records.
- Existing Partner status mutation RPC and its audit/security behavior.
- Existing voucher/redemption history when Partner status changes.
- Production asset delivery paths already verified as working.
- Environment identity boundaries and release gates.

## Last Verified Point
PASS: Archived Partner root cause identified as Admin read-model filtering, not Partner V2 rendering.
PASS: Minimal source-level migration created and merged to main.
PASS: Main and fix branch verified identical after merge.
PASS: Restore label UX improvement merged without changing status RPC, RLS, or historical business data.
PASS: XiaoE Core principle `Capability First -> Gap Type -> Smallest Correct Change` fused into xiaoe-core-v2 main.

## Re-verify Needed Before Next Mutation
Re-verify only what is relevant to the next opened issue or feature, including as applicable:
- current GitHub source / branch state,
- whether `20260821024700_admin_partner_directory_include_archived.sql` has actually been deployed to the live Supabase project,
- deployed frontend/runtime version,
- current Production/Public Smoke status if release-sensitive,
- Supabase schema / RPC / RLS state,
- active business owner/source of truth,
- affected stable paths and invariants.

Important: GitHub merge does not prove Supabase migration deployment. Runtime Archived visibility must be verified against the live database before claiming Production completion.

## Deferred / Not Deployed
- Runtime verification of Archived Partner visibility remains dependent on confirming the new Supabase migration has executed in the live environment.
- Future multi-merchant voucher network support remains deferred unless explicitly reopened.
- Future environment upgrades such as Supabase branching, Staging, canary deploys, automated rollback, alternate hosting, or CI/CD replacement remain allowed by the current Environment Contract.

## Open Issues / Blockers
- No active source-code blocker remains for Archived Partner restore/discoverability.
- Deployment state of migration `20260821024700_admin_partner_directory_include_archived.sql` is not yet verified in this checkpoint.

## Last Change
- Investigated missing Archived Partner in Partner V2.
- Proved Partner V2 already supports archived rendering.
- Traced the real blocker to `admin_partner_directory()` excluding archived rows.
- Added and merged the minimal read-model migration to include archived Partners while excluding the internal ADMIN pseudo-partner.
- Preserved existing status mutation, RLS, voucher history, redemption history, and audit paths.
- Improved archived-state UX label to `Restore Partner` without changing the underlying status contract.
- Fused the durable lesson into XiaoE Core as `Capability First -> Gap Type -> Smallest Correct Change`.
- Work session closed cleanly at 2026-08-21 02:51 +08:00.

## Next Action
On the next `小E上线`:
1. Load Behavior Logic.
2. Load Voucher Core v2.3.
3. Restore this checkpoint.
4. Re-verify only the state that could affect the newly opened task.
5. If Archived Partner visibility is revisited, first verify live Supabase deployment of `20260821024700_admin_partner_directory_include_archived.sql` before changing any code.
6. Continue from the smallest justified next action.

For release-sensitive work, use the established path:
`DEV proof -> UAT when required -> Production Gate -> deploy -> Production Smoke -> PASS or rollback/recovery`.

## Checkpoint Update Rule
At `小E收工`, update only:
- Active Goal,
- Verified Facts that materially changed,
- Protected Paths / Invariants if their verified status changed,
- Last Verified Point,
- Re-verify Needed,
- Open Issues / Blockers,
- Last Change,
- Next Action.

Do not copy chat transcripts, temporary guesses, debugging noise, or general Behavior/Core rules into this file.
