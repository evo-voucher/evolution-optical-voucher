# XIAOE_PROJECT

Status: Template
Purpose: Portable XiaoE project state and checkpoint contract.

## 1. Project Identity

- Project name:
- Repository:
- Repository owner:
- Default branch:
- Primary language / stack:
- Project owner / operator:

## 2. Environment Boundaries

- Production environment:
- Development/Test environment:
- Database/backend:
- Frontend hosting:
- Auth provider:
- Secrets location/owner:
- Production write boundary:

Unknown values must be marked `UNKNOWN`, not guessed.

## 3. Business Purpose

Describe the real business purpose of the project in plain language.

## 4. Canonical Flows

List the important end-to-end business paths.

Example format:

`User action -> UI owner -> Auth/Session -> API/RPC -> Database/business rule -> Response -> User result`

For each flow record:
- owner/source of truth,
- last verified result,
- known invariants,
- risk if changed.

## 5. Architecture Owners

Record canonical ownership only when supported by evidence.

- UI owner:
- API/RPC owner:
- business-rule owner:
- data source of truth:
- auth/tenant boundary owner:
- deployment owner:

Competing or legacy owners should be listed separately until retired.

## 6. Stable Paths

For each verified stable path:
- path name,
- date/checkpoint,
- evidence used,
- PASS criteria,
- protected invariants.

Do not modify stable paths without evidence that the root cause lies inside them.

## 7. Active Work

- Current goal:
- Active branch:
- Active PR:
- Current checkpoint:
- Last verified PASS:
- Last verified FAIL:
- Next logical action:

## 8. Known Issues / Risks

For each item:
- issue,
- severity,
- root cause known? yes/no,
- affected layer,
- Production impact,
- workaround if any,
- real fix direction.

## 9. Security Boundaries

- RLS / tenant isolation:
- role model:
- privileged functions:
- public/anonymous surfaces:
- sensitive data:
- known security warnings:

Never store passwords, service-role keys, full JWTs, or long-lived plaintext tokens in this file.

## 10. Deployment & Rollback

- deployment path:
- pre-deploy checks:
- smoke test:
- rollback method:
- last known good commit/version:

Before high-risk Production changes, rollback must be understood first.

## 11. Cost / Tool Constraints

- free-first preference:
- paid tools currently approved:
- unavailable tools:
- local environment constraints:

Free-first does not override safety or correctness.

## 12. Portable Restore Data

- last XiaoE session state:
- repository confirmed:
- branch confirmed:
- unresolved blockers:
- next startup action:

On restore, current repository evidence wins over stale checkpoint text.

## 13. Learning Retention

Retain only reusable engineering learning.

Preferred form:

`Incident -> Pattern -> Existing capability strengthened`

Avoid accumulating one-off UI details, temporary fixes, or obsolete implementation facts.

## 14. Completion Check

Before XiaoE signs off:
- root cause identified or bounded by evidence,
- responsible layer repaired,
- affected real path verified,
- regression scope justified,
- rollback/checkpoint recorded,
- durable learning retained,
- temporary debugging noise discarded.
