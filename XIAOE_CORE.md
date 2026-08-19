# XiaoE Core Engineering Protocol

Version: 2.2
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

When Eric says 「小E上线」 for Evolution Voucher, use this compact startup flow:

`Load Behavior -> Load Voucher Core -> Restore Checkpoint -> Re-verify changed state -> Lock active business path -> Work`

Operationally:
- Apply `XIAOE_BEHAVIOR_LOGIC_V1.md` first.
- Use this file only for Voucher-specific execution.
- Restore `XIAOE_CHECKPOINT.md` as continuation context, not live truth.
- Re-verify any GitHub / Supabase / runtime state that may have changed.
- Lock the current business path, owner/source of truth, scope, protected invariants, and verification target before mutation.

The active stability chain remains inherited from Behavior Logic:

`FACT FIRST -> OWNER FIRST -> SCOPE FIRST -> STABLE PATH LOCK -> ONE CHANGE AT A TIME -> RE-VERIFY`

Stop/reassess behavior is inherited from the current Behavior Logic and must not be duplicated or weakened here.

## 2. Voucher Project Objective

Evolution Voucher is a B2B2C multi-merchant voucher and redemption platform.
Engineering decisions must preserve clear business ownership, tenant isolation, voucher integrity, traceable issuance/redemption state, and safe expansion to additional voucher types and partners.

Do not solve a local UI symptom by weakening the business model, permission model, or data ownership.

## 3. Voucher Domain Invariants

These are Voucher-specific protected invariants. A change is not successful if it fixes the target symptom but breaks one of these without an intentional approved business redesign.

- A voucher must not be redeemed more than allowed by its authoritative business rule.
- Redemption state must be traceable to the authoritative voucher / redemption records.
- A Partner must not see or control another Partner's private tenant data unless an explicit cross-tenant business rule authorizes it.
- Staff capabilities must remain limited to the branch / merchant / redemption scope intentionally granted to that staff identity.
- Admin visibility and aggregation must not be achieved by weakening tenant isolation or normal permission enforcement.
- Issued / distributed / claimed / redeemed / remaining quantities or values must reconcile to authoritative source records and their defined business meaning.
- Historical voucher scope that is intentionally snapshotted at issuance must not silently change because later configuration changes.
- UI state must not become a substitute for backend authorization, voucher validity, redemption integrity, or canonical totals.
- Existing verified business paths remain protected until evidence shows that a required change belongs inside them.

Protection is evidence-based. A domain invariant may change only as part of an explicit business-model decision with corresponding data, permission, migration, and regression analysis.

## 4. Voucher Business Definition & Number Ownership

Before changing statistics, reports, states, permissions, or workflows, define the business meaning and canonical owner.

Relevant concepts may include:
- allocation,
- claimed,
- issued / distributed,
- redeemed,
- balance / remaining,
- partner ownership,
- merchant / redemption ownership,
- customer-facing voucher state.

For every important number or state, XiaoE must be able to answer:
- What exactly does it mean?
- Which record, transaction set, function, RPC, or business rule owns it?
- Is it stored, derived, or snapshotted?
- Which role may see it?
- Which role or process may change the underlying state?
- How does it reconcile with the authoritative transaction records?

Business-number rule:
- Dashboard and report numbers must derive from the canonical business owner, not from a second UI-only calculation.
- If the same metric exists in multiple places, they must share one business definition and reconcile to the same authoritative records.
- Do not infer `balance` merely from convenient visible numbers unless the defined business model explicitly makes that formula authoritative.
- Do not invent fields, statuses, formulas, relationships, or fallback totals merely to make a card or report look complete.
- If a number cannot yet be defined unambiguously, expose the uncertainty rather than creating a silent approximation.

## 5. Roles, Permissions & Tenant Isolation

Typical roles include:
- Admin / Platform,
- Partner / Merchant,
- Redemption Staff,
- Customer.

Voucher work must preserve role boundaries:
- A Partner must not gain access to another Partner's private data through UI, RPC, API, direct query, or shared-link behavior.
- Staff access must remain limited to the redemption capabilities intentionally granted to that staff role.
- Admin aggregation must not be implemented by weakening tenant isolation.
- UI hiding is not a permission boundary.
- Auth, RLS, RPC authorization, and server-side ownership rules remain authoritative where applicable.
- Never weaken JWT verification, RLS, tenant isolation, or identity boundaries to make a test pass.

## 6. Voucher Flow & Owner Tracing

For a fault, trace only the affected business flow first.

Common execution path:

`User Action -> UI -> Session/Auth -> API/RPC/Edge -> Database/Business Rule -> Response -> Rendered Result`

Common voucher lifecycle direction:

`Allocation/Creation -> Claim/Distribution -> Customer Use -> Redemption -> Reporting`

Not every feature uses every stage. Verify the actual active path before assuming a lifecycle step exists.

Before repair, identify the canonical owner of the result.
Examples:
- A reporting total may be owned by a database aggregate or RPC, not by the visible card.
- Redemption validity may be owned by a backend function or database rule, not by the button.
- Partner visibility may be owned by Auth/RLS/tenant filtering, not by frontend hiding.

Do not create a second calculation, duplicate handler, client-side compensation, or parallel permission path when the real owner can be repaired.
When multiple implementations appear to compete, determine which one actually executes in the user's real path and converge toward one source of truth.

## 7. Targeted Voucher Debug

Project-specific execution pattern:

**局部故障，局部追根；跨层根因，才扩大范围。**

`Fault -> Lock Voucher Path -> Verify Business Meaning -> Verify Owner/Contract -> Focused Test -> Targeted E2E -> PASS -> Stop`

Do not widen the task because nearby code is old, imperfect, or easy to refactor.
Do not treat disappearance of an error message as PASS.
PASS means the intended Voucher business result works and the protected domain invariants still hold.

## 8. Stable Voucher Paths

Verified stable Voucher paths are protected baselines.

**稳定链保护｜新增功能围绕正式 Owner 扩展｜已 PASS 主链非根因不动**

Potentially protected paths include verified:
- Admin login,
- Partner login and tenant isolation,
- Staff access,
- voucher issuance/distribution,
- redemption,
- reporting,
- production asset delivery.

Protection is not permanent immunity. If evidence proves a protected path contains the root cause or must change for a real business requirement, change it deliberately and re-verify the affected invariant and business path.

## 9. Client Delivery & Runtime Verification

For this Voucher frontend, repository state is not sufficient proof of user runtime state.

When source appears correct but the device behaves differently, verify as relevant:

`Source -> Deploy -> Entry Loader -> Asset Version -> Browser Cache -> Local/Session State -> Executed Runtime`

Do not rewrite correct Voucher business logic merely to compensate for an unverified stale-client or asset-delivery problem.
A Git commit is not proof that the user's device executed the new code.

## 10. Test Escalation

Use the smallest test that can reliably prove the affected Voucher path.

- **L1 — Source / Contract Check:** selectors, arguments, RPC names, contracts, static logic, duplicate ownership, asset references.
- **L2 — Local Logic Test:** focused function, SQL contract, mock, aggregate reconciliation, or direct backend path.
- **L3 — Targeted E2E:** minimum real runtime proving the complete affected business flow and relevant domain invariants.
- **L4 — Full Regression:** major schema/architecture change, Auth/RLS/security boundary change, release/cutover, shared infrastructure impact, repeated failed repair, or explicit request.

Do not run broad regression by default when targeted proof is sufficient.
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
- canonical ownership is unchanged unless intentionally redesigned,
- permissions remain bounded,
- read/write semantics are unchanged unless intentionally approved,
- post-deploy checks confirm the intended contract exists.

Write-path / Auth / RLS / identity / redemption / issuance / destructive changes:
- require stronger proof,
- require rollback awareness,
- protect valid Production data and Voucher domain invariants.

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

Free-first never overrides security, tenant isolation, correctness, data integrity, or Voucher domain invariants.
Paid or stronger-isolation steps require Eric's approval when they are genuinely necessary.

## 14. Autonomous Repair Boundary

XiaoE may proceed without interruption when an action is:
- free,
- reversible,
- limited to the active Voucher scope,
- non-destructive to Production data,
- security-preserving,
- invariant-preserving,
- and does not change a major business rule without evidence.

Ask before:
- paid operations,
- irreversible or high-impact Production changes,
- destructive data operations,
- identity/MFA/password steps requiring Eric,
- major architecture or cutover decisions,
- intentional changes to Voucher domain invariants or core business semantics,
- security weakening,
- physical-device-only verification that cannot be simulated reliably.

## 15. Completion Standard

Voucher work is complete when:
- the relevant business meaning is clear,
- current facts are verified,
- the canonical owner / source of truth is identified,
- the scope is justified,
- the responsible layer is repaired,
- Voucher domain invariants still hold,
- related stable paths remain working,
- important totals/states reconcile to authoritative records where relevant,
- the affected real business path passes,
- deployment/runtime checks pass where relevant,
- rollback/recovery is understood for Production changes,
- remaining manual-only verification is clearly stated.

## 16. 「小E收工」

Use this compact closeout flow:

`Record verified state -> PASS/FAIL -> unresolved -> smallest next action -> checkpoint`

Update `XIAOE_CHECKPOINT.md` with only durable continuation state:
- current verified engineering state,
- last verified PASS / FAIL point,
- unresolved blockers or deferred items,
- smallest logical next action,
- what is live fact versus memory/assumption.

Do not copy general Behavior Logic into the checkpoint.
Do not promote temporary debugging noise into permanent project rules.
The next 「小E上线」 should be able to continue from the checkpoint without restarting diagnosis, while still re-verifying any state that may have changed.