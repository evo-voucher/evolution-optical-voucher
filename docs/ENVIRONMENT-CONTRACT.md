# Evolution Voucher Environment Contract

Version: 1.1
Status: Active project execution contract
Scope: Evolution Voucher development, UAT, release and Production environment boundaries

## 1. Purpose

This contract defines environment responsibilities and release boundaries without permanently binding the system to one provider, project ID, hosting platform, branch name or deployment topology.

Principle:

**Freeze safety rules, not future architecture.**

Environment roles are durable. Current implementations are replaceable when a verified migration or architecture decision requires it.

## 2. Authority Boundary

This document belongs to the Voucher project execution layer.
It does not modify or redefine `XIAOE_BEHAVIOR_LOGIC_V1.md`.

Priority remains:

`XIAOE_BEHAVIOR_LOGIC_V1.md -> XIAOE_CORE.md -> Environment Contract -> XIAOE_CHECKPOINT.md`

If current runtime evidence contradicts any environment mapping recorded here, treat the mapping as stale, stop environment-changing work, re-verify identity, and update the current implementation section only after evidence is sufficient.

## 3. Durable Environment Roles

### DEV

Purpose: isolated engineering and fault-reproduction environment where failure is acceptable.

DEV may:
- run local or remote test backends,
- use disposable/test data,
- reset/rebuild test databases,
- run focused and broad automated tests,
- host incomplete feature branches,
- simulate migrations and business flows reversibly.

DEV must not:
- mutate authoritative Production business data,
- use Production secrets or privileged credentials in client code,
- be presented as proof that Production is correct,
- silently become the customer-facing runtime.

### UAT

Purpose: release-candidate business acceptance environment that proves realistic user flows before Production.

UAT must:
- use a pinned/identifiable release candidate,
- have an explicit non-Production deployment role,
- preserve the same business contracts expected in Production where fidelity matters,
- use test identities/test records or another verified isolation method,
- prove the relevant Admin/Partner/Staff/Customer journey for L3/L4 changes.

UAT must not:
- write to authoritative Production business data unless a separately approved read-only/controlled verification path is explicitly required,
- share an ambiguous deployment identity with Production,
- be treated as PASS merely because pages load.

### PRODUCTION

Purpose: authoritative live customer/business runtime.

Production must:
- have one verified current runtime identity,
- accept only release candidates that passed the required gate,
- preserve rollback/recovery awareness,
- receive post-deploy smoke/runtime verification,
- fail closed when environment identity is ambiguous or contradicts the expected release target.

Production must not:
- be used as the default experimentation environment,
- receive unverified high-impact schema/Auth/RLS/issuance/redemption changes,
- use test data manipulation to force a green verification result.

## 4. Environment Identity Rule

An environment identity is not just a label such as `environment: 'production'`.
It is the verified tuple:

`role + source ref + deployed URL + backend project + data semantics + release candidate/version`

The deployment role and the backend compatibility mode are separate facts. A UAT surface may temporarily execute a production-compatible contract while remaining explicitly non-authoritative; in that case the deployment role must still be declared as UAT and authoritative Production data must remain protected.

Before any persistent mutation or release, XiaoE must verify the relevant tuple rather than trusting a filename, folder, remembered project ID or UI label.

Project IDs, URLs and branch names are **current implementation data**, not eternal architecture.
They may be replaced through an explicit, verified migration/cutover.

## 5. Current Verified / Audited Mapping

Status date: 2026-08-19

### Production candidate mapping

- Role: PRODUCTION
- Git source: `main`
- Public site: `https://evo-voucher.github.io/evolution-optical-voucher/`
- Authoritative target according to current Readiness + Production Smoke contract: `hukihbcyyqhanaqrizvm`
- Verification status: **DOCUMENTED/WORKFLOW-VERIFIED, LIVE CONNECTOR ACCESS NOT CURRENTLY AVAILABLE**
- Historical readiness baseline records 43 vouchers / 8 redemptions after production smoke.

Rule: do not rewrite Production target identity based only on another accessible Supabase project. Re-verify the real deployed runtime before any Production target correction or cutover.

### Development / rebuild candidate mapping

- Role: DEV candidate
- Backend project currently accessible: `xfivcfwexcxsyiylgryn`
- Supabase status at audit: ACTIVE_HEALTHY
- Current audit data: 2 partners, 7 branches, 1 voucher, 1 redemption, 2 voucher versions
- Current Supabase development branches: none
- Verification status: **STRONG DEV/REBUILD CANDIDATE, NOT AUTHORITATIVE PRODUCTION**

Reason: the observed dataset materially differs from the documented Production baseline.

### UAT mapping

- Frontend harnesses: `/uat/` and `/uat-preview/`
- `/uat/loader.js` pins a candidate commit, which is suitable for immutable release-candidate testing.
- `/uat-preview/` contains Admin/Partner/Staff/Voucher/Voucher Engine surfaces.
- `uat-preview/assets/js/backend-config.js` currently points to `xfivcfwexcxsyiylgryn`.
- The UAT preview now declares `role: 'uat'` and `authoritativeData: false`.
- Its existing `environment: 'production'` value is retained temporarily as a compatibility-mode field and must not be interpreted as deployment authority.
- Verification status: **UAT DEPLOYMENT ROLE EXPLICIT; BACKEND FORMALIZATION STILL PARTIAL**

Rule: until the backend identity is formally promoted as the UAT target, treat `/uat-preview/` as a preview/test surface with explicit non-Production authority, not proof of a final isolated UAT backend topology.

## 6. Release Routing by Existing L1-L4 Ladder

The Environment Contract does not create a new risk scale.
It uses `XIAOE_CORE.md` L1-L4.

- **L1:** DEV/source-level verification normally sufficient; Production release still requires the relevant syntax/delivery smoke.
- **L2:** DEV/local or focused backend verification required; UAT only when the business result cannot be reliably proven locally.
- **L3:** DEV + targeted UAT business-path proof before Production.
- **L4:** DEV + UAT + full required regression + explicit Production gate/approval/recovery path before Production.

Any task that changes environment identity, Auth/RLS/security boundary, schema/migration, issuance/redemption integrity, or destructive persistent data is never downgraded merely because the code diff is small.

## 7. Production Gate

A release candidate may enter Production only when all applicable items are true:

1. target environment tuple is VERIFIED,
2. required L1-L4 proof has passed,
3. candidate commit/version is identifiable,
4. no unresolved tenant/Auth/RLS/data-integrity regression exists,
5. rollback/recovery target is known,
6. deployment succeeds,
7. Production smoke/runtime verification passes,
8. failure does not get hidden by patching Production data.

A successful Git merge, deploy job or migration alone is not sufficient.

## 8. Environment Drift Gate

Stop release/mutation when any of the following disagree unexpectedly:

- frontend backend-config target,
- Production smoke expected target,
- Readiness/current environment contract,
- actual Supabase project identity,
- deployed public runtime,
- expected data semantics/baseline.

When drift is detected:

`STOP -> identify real runtime -> classify stale record/config -> correct only the owning environment artifact -> re-run gate`

Do not resolve drift by making all environments point to the easiest currently accessible backend.

An automated repository gate now runs `scripts/check-environment-contract.sh`. It checks that Readiness and Production Smoke agree, that the root Production backend config matches that contract, that UAT has an explicit non-Production role, and that public UAT config contains no privileged credential markers.

Current gate result during this audit: **EXPECTED FAIL / BLOCKED** because root `assets/js/backend-config.js` points to `xfivcfwexcxsyiylgryn` while Readiness and Production Smoke both require `hukihbcyyqhanaqrizvm`.

This failure is a safety result, not a request to rewrite either side by assumption. The next action is live Production identity verification.

## 9. Future Extensibility

This contract intentionally permits future changes such as:

- replacing GitHub Pages,
- moving to another Supabase project,
- introducing Supabase branching,
- adding Staging/Preview/Performance environments,
- adding region-specific environments,
- changing branch strategy,
- replacing CI/CD tooling,
- introducing automated rollback or canary deployment.

Such changes do not require changing the durable role definitions unless the business/operational model itself changes.
Only the current implementation mapping and release mechanics should be updated.

## 10. Current Audit Result

Current maturity: **PARTIAL READY / RELEASE BLOCKED ON IDENTITY DRIFT**.

Strengths:
- local Supabase + browser E2E exist,
- targeted workflows exist,
- UAT/preview surfaces exist,
- UAT now has an explicit non-Production deployment role,
- Production smoke exists,
- automated environment identity gate exists,
- rollback/readiness rules exist.

Remaining convergence work:
- formally converge DEV identity,
- formally converge the UAT backend target,
- re-verify the real Production runtime target because current repository config and Production Smoke/Readiness disagree,
- then close the promotion gate between candidate -> UAT -> Production.

Until that convergence is complete, environment-changing work must remain branch-first and must not rewrite Production identity by assumption.
