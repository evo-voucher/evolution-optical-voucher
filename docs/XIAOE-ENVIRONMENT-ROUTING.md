# XiaoE Environment Routing Contract

Version: 1.0
Status: Active second-layer execution companion
Scope: Evolution Voucher only

## Purpose

This document connects XiaoE's existing L1-L4 task-routing logic to the Development / UAT / Production environment contract.

It belongs to the project execution layer. Behavior Logic is not modified by this routing contract.

Priority remains:

`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> ENVIRONMENT-CONTRACT.md -> this routing companion -> XIAOE_CHECKPOINT.md`

## Routing Principle

XiaoE must select the smallest environment path that can reliably prove the affected business result and protected invariants.

Do not send every task through full UAT/Production merely because the system is important.
Do not keep a high-impact task in DEV only merely because the code diff is small.

## Existing L1-L4 Mapping

- L1 -> DEV/source proof
  - presentation-only, selector, text, local frontend behavior, static contract.
  - use source/static/local verification first.
  - Production release still requires applicable syntax/delivery smoke.

- L2 -> DEV/focused backend proof
  - local business logic, reporting/read-model logic, focused RPC/SQL contract, one-module behavior.
  - use local Supabase, focused test, reconciliation, or equivalent isolated proof.
  - add UAT only when the real business result cannot be proven reliably in DEV.

- L3 -> DEV + UAT targeted business-path proof
  - issuance, allocation workflow, redemption, partner/staff lifecycle, cross-role or cross-layer behavior.
  - DEV must pass first.
  - then prove the minimum realistic UAT business journey.
  - Production remains blocked until the candidate commit/version and environment identity are verified.

- L4 -> DEV + UAT + full required regression + explicit Production gate
  - Auth/RLS/security boundary, schema/migration, environment identity, cutover/shared infrastructure, destructive/high-impact persistent change, repeated failed repair.
  - require rollback/recovery awareness and explicit Production approval when applicable.
  - Production smoke/runtime verification is mandatory after release.

## Automatic Environment Selection

For every task, use this tuple from XIAOE_CORE:

`Business object -> authoritative owner -> effect type -> blast radius -> protected invariant -> minimum proof level`

Then resolve the environment route:

- Local + non-authoritative -> DEV.
- Module + authoritative read logic -> DEV, UAT only if needed for proof.
- Cross-role/write path -> DEV then UAT.
- Security/structural/system/persistent -> DEV then UAT then Production Gate.

## Environment Identity Gate

Before any persistent environment-changing action, verify the environment tuple:

`role + source ref + deployed URL + backend project + data semantics + release candidate/version`

If any critical identity component is ambiguous or conflicts with current verified evidence:

`STOP -> verify runtime identity -> classify stale artifact -> correct only the owner -> re-run gate`

Do not solve identity drift by redirecting all environments to the easiest accessible backend.

## Promotion Rules

A candidate may move forward only when the current level is actually proven:

`DEV PASS -> eligible for UAT when required`

`UAT PASS -> eligible for Production review when required`

`Production Gate PASS -> eligible for release`

`Production deploy -> smoke/runtime verify -> PASS or rollback/recovery`

A Git commit, PR merge, migration success, page load, or absence of visible errors is not by itself a promotion PASS.

## Speed Rule

Routing should stop expanding once owner, impact, invariants and minimum proof are sufficiently verified.

Small/low-risk bugs should remain fast.
High-impact work should automatically gain stronger isolation and proof.

Target behavior:

**small bug = fast and local**

**core bug = isolated and deeply verified**

**Production = protected, never the default test environment**

## Current Audit State

As of 2026-08-19:

- UAT preview has an explicit non-Production deployment role.
- Environment Contract Gate exists and is active on the audit branch.
- Current gate is intentionally BLOCKED because repository root Production backend config and documented/smoke Production target disagree.
- No Production identity correction is authorized until live Production identity is re-verified.

This blocked state is expected safety behavior and must not be bypassed merely to make CI green.
