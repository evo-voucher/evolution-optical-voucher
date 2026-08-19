# XiaoE Core Engineering Protocol

Version: 2.1
Status: Active
Scope: Evolution Voucher engineering work only.

## 0. Authority & Responsibility

This file is the project execution protocol for Evolution Voucher.
It does not redefine XiaoE's general reasoning constitution.

Authoritative general behavior:
`evo-voucher/xiaoe-core-v2/core/behavior/XIAOE_BEHAVIOR_LOGIC_V1.md`

Project state:
`XIAOE_CHECKPOINT.md`

Priority:
`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> XIAOE_CHECKPOINT.md`

Meaning:
- Behavior Logic governs how XiaoE reasons and controls change.
- XIAOE_CORE governs how those principles are applied inside Evolution Voucher.
- XIAOE_CHECKPOINT records the current verified project state and continuation point.
- Project state must never override verified facts, security, or the higher-level behavior constitution.

## 1. Trigger: 「小E上线」

When Eric says 「小E上线」 for the Evolution Voucher project, use this sequence:

1. Apply `XIAOE_BEHAVIOR_LOGIC_V1.md` first.
2. Enter this Evolution Voucher project protocol.
3. Restore `XIAOE_CHECKPOINT.md`.
4. Verify the relevant current GitHub / Supabase / runtime state before relying on checkpoint memory.
5. Lock the affected business path.
6. Identify the verified owner / source of truth.
7. Make only the smallest justified change.
8. Re-verify the affected real path and any related protected stable path.

The active stability chain is inherited from Behavior Logic:

`FACT FIRST -> OWNER FIRST -> SCOPE FIRST -> STABLE PATH LOCK -> ONE CHANGE AT A TIME -> RE-VERIFY`

If the same repair direction fails twice:

`STOP -> Re-check Fact -> Owner -> Scope -> Architecture`

## 2. Voucher Project Objective

Evolution Voucher is a B2B2C multi-merchant voucher and redemption platform.
Engineering decisions must preserve clear business ownership, tenant isolation, voucher integrity, traceable issuance/redemption state, and safe expansion to additional voucher types and partners.

Do not solve a local UI symptom by weakening the business model, permission model, or data ownership.

## 3. Voucher Business Definition First

Before changing statistics, reports, states, permissions, or workflows, define the business meaning and source of truth.

Relevant concepts may include:
- allocation,
- claimed,
- issued / distributed,
- redeemed,
- balance / remaining,
- partner ownership,
- merchant / redemption ownership,
- customer-facing voucher state.

Do not invent a field, status, formula, or relationship because it is convenient for the UI.

For every important number or state, XiaoE should be able to answer:
- What does it mean?
- Which record or function owns it?
- Is it derived or stored?
- Which role is allowed to see or change it?
- How does it reconcile with the underlying transaction records?

## 4. Roles, Permissions & Tenant Isolation

Voucher work must preserve role boundaries.

Typical roles include:
- Admin / Platform,
- Partner / Merchant,
- Redemption Staff,
- Customer.

Rules:
- A Partner must not gain access to another Partner's private data through UI, RPC, API, direct query, or shared link behavior.
- Staff access must remain limited to the redemption capabilities intentionally granted to that staff role.
- Admin aggregation must not be implemented by weakening tenant isolation.
- UI hiding is not a permission boundary.
- Auth, RLS, RPC authorization, and server-side ownership rules remain authoritative where applicable.
- Never weaken JWT verification, RLS, tenant isolation, or identity boundaries to make a test pass.

## 5. Voucher Flow Thinking

For a fault, trace only the affected business flow first.

Common execution path:

`User Action -> UI -> Session/Auth -> API/RPC/Edge -> Database/Business Rule -> Response -> Rendered Result`

Common voucher lifecycle direction:

`Allocation/Creation -> Claim/Distribution -> Customer Use -> Redemption -> Reporting`

Not every feature uses every stage. Verify the actual active path before assuming a lifecycle step exists.

If evidence shows the root cause crosses layers, expand the scope only as far as the evidence requires.

## 6. Source of Truth & Owner

Before repair, identify the canonical owner of the result.

Examples:
- A reporting total may be owned by a database aggregate or RPC, not by the visible card.
- Redemption validity may be owned by a backend function or database rule, not by the button.
- Partner visibility may be owned by Auth/RLS/tenant filtering, not by frontend hiding.

Do not create a second calculation, duplicate handler, client-side compensation, or parallel permission path when the real owner can be repaired.

When multiple implementations appear to compete, determine which one actually executes in the user's real path and converge toward one source of truth.

## 7. Targeted Root Debug

Core project rule:

**局部故障，局部追根；跨层根因，才扩大范围。**

Default flow:

`Fault -> Lock Path -> Verify Owner/Contract -> Local Logic Test -> Targeted E2E -> PASS -> Stop`

Do not widen the task merely because nearby code is old, imperfect, or easy to refactor.

Do not treat disappearance of an error message as PASS.
PASS means the intended Voucher business result works correctly.

## 8. Stable Path Protection

A Voucher path that has passed real verification is a protected baseline.

**稳定链保护｜新增功能围绕正式 Owner 扩展｜已 PASS 主链非根因不动**

Examples of potentially protected paths include verified:
- Admin login,
- Partner login and tenant isolation,
- Staff access,
- voucher issuance/distribution,
- redemption,
- reporting,
- production asset delivery.

Protection is evidence-based, not permanent immunity.
If a protected path is proven to contain the root cause or must change for a real business requirement, it may be changed deliberately and then re-verified.

## 9. Client Delivery & Runtime Verification

For this Voucher frontend, repository state is not sufficient proof of user runtime state.

When source appears correct but the device behaves differently, verify as relevant:

`Source -> Deploy -> Entry Loader -> Asset Version -> Browser Cache -> Local/Session State -> Executed Runtime`

Do not rewrite correct Voucher business logic merely to compensate for an unverified stale-client or asset-delivery problem.

A Git commit is not proof that the user's device executed the new code.

## 10. Test Escalation

Use the smallest test that can reliably prove the affected Voucher path.

- **L1 — Source / Contract Check:** selectors, arguments, RPC names, contracts, static logic, duplicate ownership, asset references.
- **L2 — Local Logic Test:** focused function, SQL contract, mock, or direct backend path.
- **L3 — Targeted E2E:** minimum real runtime proving the complete affected business flow.
- **L4 — Full Regression:** major schema/architecture change, Auth/RLS/security boundary change, release/cutover, shared infrastructure impact, repeated failed repair, or explicit request.

Do not run broad regression by default when a targeted test is sufficient.
Do not skip broader proof when the changed layer justifies it.

## 11. Production Gate

Before a Production-changing action, verify what is relevant to the changed layer and know the rollback path.

Frontend / HTML / JavaScript as applicable:
- syntax parses,
- intended replacement or selector actually matches,
- generated/injected code is valid,
- page bootstrap reaches expected state,
- mobile interaction remains usable,
- intended asset version is actually delivered.

RPC / database / reporting as applicable:
- business definitions match the intended meaning,
- aggregate formulas reconcile against source records,
- permissions remain bounded,
- read/write semantics are unchanged unless intentionally approved,
- post-deploy checks confirm the intended contract exists.

Write-path / Auth / RLS / identity / redemption / issuance / destructive changes:
- require stronger proof,
- require rollback awareness,
- protect valid Production data.

A mergeable PR, successful migration, or successful deploy is not by itself proof of runtime correctness.

## 12. Rollback Readiness

Before Production mutation, know the immediate recovery path to the last verified stable state.

Possible rollback anchors:
- previous Git commit or revert target,
- prior function definition or migration recovery path,
- prior asset version,
- reversible configuration state.

Rollback must not require weakening security or deleting valid Production data unless explicitly approved.

## 13. Development Isolation & Free-First

Prefer Development/Test verification before Production when practical and justified.

Free-first is preferred only when it preserves the required safety and proof.

Useful low-cost methods may include:
- development branches,
- read-only Production queries for evidence,
- static source checks,
- targeted UAT,
- focused local logic tests,
- reversible asset/version strategies.

Free-first never overrides security, tenant isolation, correctness, or data integrity.
Paid or stronger-isolation steps require Eric's approval when they are genuinely necessary.

## 14. Autonomous Repair Boundary

XiaoE may proceed without interruption when an action is:
- free,
- reversible,
- limited to the active Voucher scope,
- non-destructive to Production data,
- security-preserving,
- and does not change a major business rule without evidence.

Ask before:
- paid operations,
- irreversible or high-impact Production changes,
- destructive data operations,
- identity/MFA/password steps requiring Eric,
- major architecture or cutover decisions,
- security weakening,
- physical-device-only verification that cannot be simulated reliably.

## 15. Completion Standard

Voucher work is complete when:
- the relevant business meaning is clear,
- current facts are verified,
- the canonical owner / source of truth is identified,
- the scope is justified,
- the responsible layer is repaired,
- unrelated systems were not changed,
- related stable paths remain working,
- the affected real business path passes,
- deployment/runtime checks pass where relevant,
- rollback/recovery is understood for Production changes,
- remaining manual-only verification is clearly stated.

## 16. 「小E收工」

Before stopping:
1. Update `XIAOE_CHECKPOINT.md` with the current verified engineering state.
2. Record the last verified PASS / FAIL point.
3. Record unresolved blockers.
4. Record the smallest logical next action.
5. Distinguish verified runtime facts from assumptions or memory.
6. Do not copy general Behavior Logic into the checkpoint.
7. Do not promote temporary debugging noise into permanent project rules.

The next 「小E上线」 should be able to continue from the checkpoint without restarting diagnosis, while still re-verifying any state that may have changed.