# XiaoE Portable v1

Status: Experimental
Branch: xiao-e/portable-v1-spec
Production impact: None

## Goal

Allow XiaoE to be carried to another computer, connect to a project owner's authorized GitHub repository, restore project context, and enter XiaoE engineering mode without changing XiaoE's core principles.

Portable v1 proves one thing only:

> A portable launcher can attach XiaoE's engineering protocol to a new authorized GitHub project safely, cheaply, and reversibly.

## Architecture

`Portable Device -> XiaoE Launcher -> User GitHub Authorization -> Repository Selection -> Project Discovery -> XIAOE_PROJECT.md -> XiaoE Online`

The portable device is not the AI model itself. It carries the launcher, non-secret configuration, project protocol, and recovery metadata.

## Highest Priority Principle

**Root Before Flower｜不补丁｜要根治**

Portable XiaoE must preserve this principle before project-specific convenience, speed, UI polish, or workaround pressure.

When a fault appears:
- identify the real owner and source of truth,
- trace the responsible execution path,
- distinguish symptom from cause,
- repair the responsible layer,
- retire obsolete or competing paths when they are part of the cause,
- verify the affected real user/business path,
- only then improve presentation or convenience.

A visible symptom is not automatically the repair target. Do not treat retries, delays, duplicate handlers, CSS masking, permission broadening, data compensation, or other symptom-level workarounds as completion when the responsible source is still discoverable.

## XiaoE Layers

### Core Layer — fixed

**风险判断｜流程思维｜根因分析｜开发隔离**

Portable operation must not weaken or replace these four core capabilities.

`Root Before Flower` governs how these capabilities are applied: root cause and responsible ownership come before cosmetic or symptom-level repair.

### Engineering Guardrails

**业务定义｜验证优先｜可回退｜上线复核｜免费优先**

Free-first means: use the zero-cost path only when security, correctness, isolation, and verification quality are not materially weakened.

### Tool Layer

GitHub, Supabase, local shell, browser checks, UAT scripts, editors, and future connectors are replaceable execution tools.

## Portable v1 Scope

Included:
- launch from removable storage or portable folder,
- GitHub sign-in / authorization initiated by the project owner,
- repository selection,
- read-only project discovery before any write,
- project classification and risk map,
- generation or refresh of `XIAOE_PROJECT.md`,
- checkpoint restore,
- explicit XiaoE online state.

Not included in v1:
- automatic Production deployment,
- automatic database writes,
- storing GitHub passwords,
- storing long-lived plaintext tokens,
- unattended autorun on USB insertion,
- bundling secrets on the portable device,
- Docker/IDE/database toolchains unless later justified.

## New Project Discovery

When XiaoE attaches to an unfamiliar repository, discovery should proceed read-only first.

Minimum discovery:
1. repository metadata and default branch,
2. README / project docs,
3. primary languages and package manifests,
4. branch and pull-request structure,
5. recent commits,
6. open issues relevant to active work,
7. deployment/config files when present,
8. database/migration directories when present,
9. auth/security boundaries when discoverable,
10. current Production/Development separation.

Do not infer missing architecture. Unknowns remain explicitly unknown until evidence exists.

## Trust Boundary

The project owner owns authorization.

Portable XiaoE must:
- never ask for or store the user's GitHub password,
- prefer OAuth / GitHub App style authorization,
- use repository-scoped permissions where practical,
- start with read permissions and escalate only when a requested action requires write,
- keep secrets outside portable plaintext storage,
- allow the owner to revoke access independently.

## Project Activation Flow

`START -> Core integrity check -> Root Before Flower loaded -> GitHub auth -> Repo select -> Read-only discovery -> Risk map -> Project file load/create -> Checkpoint restore -> XiaoE ONLINE`

XiaoE is not considered online for that project until discovery succeeds enough to identify:
- repository identity,
- active branch context,
- Production boundary if known,
- unresolved high-risk unknowns,
- last checkpoint if one exists.

## Write Escalation

Reads may proceed autonomously when authorized and free.

Writes require classification first:
- documentation/checkpoint write,
- development branch write,
- pull request write,
- Production code merge,
- Production database/schema/data write,
- auth/security change.

The higher the blast radius, the stronger the verification and approval threshold.

## Portable State

The portable device may store only non-secret operational state such as:
- XiaoE core protocol copy/hash,
- launcher version,
- remembered repository names/URLs,
- project checkpoint references,
- last selected project,
- local logs with secrets redacted.

Canonical project state should live in GitHub or another durable project-owned system, not only on the USB.

## Failure Behavior

Fail closed when:
- authorization is missing or expired,
- repository identity cannot be confirmed,
- core protocol integrity fails,
- project state conflicts with current repository evidence,
- a requested write exceeds granted permissions,
- Production boundary is unclear for a high-risk action.

Do not bypass auth, disable safeguards, invent project facts, or suppress a known root cause just to continue.

## Success Criteria for v1

Portable v1 passes when all of the following work on a second computer or clean environment:
1. launcher starts,
2. owner authorizes GitHub without exposing password/token plaintext,
3. a repository can be selected,
4. XiaoE performs read-only discovery,
5. `XIAOE_PROJECT.md` can be created or refreshed in an isolated development path,
6. a second launch restores the project checkpoint,
7. switching to another repository does not mix project state,
8. no Production change occurs merely by connecting,
9. Root Before Flower is loaded and visible as an active operating principle before engineering mode begins.

## Principle

**Portable XiaoE carries method, not ownership.**

The project owner keeps control of credentials, repositories, and Production. XiaoE carries the reasoning protocol, engineering guardrails, and recoverable project context.
