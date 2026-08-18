# XiaoE Portable v1

Status: Draft MVP Specification
Scope: Portable XiaoE engineering bootstrap for authorized GitHub projects.

## Goal

Allow XiaoE to arrive at a new computer and an authorized GitHub repository, restore the XiaoE engineering method, understand the project quickly, and establish a safe working checkpoint without carrying project secrets on the USB device.

Target experience:

`Insert USB -> Start XiaoE Launcher -> Project owner authorizes GitHub -> Select repository -> XiaoE inspects project -> Project profile/checkpoint created -> XiaoE online`

This is not a portable AI model. The portable device carries the XiaoE operating protocol and bootstrap tooling; the repository remains the source of project code, and authenticated services remain the source of external project data.

## Non-Negotiable Core

The portable edition must preserve the XiaoE core:

**风险判断｜流程思维｜根因分析｜开发隔离**

Engineering guardrails:

**业务定义｜验证优先｜可回退｜上线复核｜免费优先**

Portable operation must never weaken these principles for convenience.

## Security Model

### USB may contain
- XiaoE core protocol.
- Launcher binaries/scripts.
- Non-sensitive configuration.
- Project templates.
- Local checkpoint metadata that contains no secrets.
- Optional cached public repository metadata.

### USB must not contain in plaintext
- GitHub passwords.
- Long-lived personal access tokens.
- Supabase service-role keys.
- Database passwords.
- Full JWTs.
- MFA recovery codes.
- Customer/private project data unless explicitly encrypted and approved.

### Authentication

Preferred GitHub connection:
1. GitHub App or OAuth authorization.
2. Project owner authenticates directly with GitHub.
3. Grant repository-scoped access where possible.
4. Minimum required permission first.
5. Credentials remain in OS secure storage or provider-managed session, not project files or USB plaintext.
6. Access must be revocable by the project owner.

## Project Admission Flow

When XiaoE connects to a repository for the first time:

### Step 1 — Establish identity and authority
- Confirm authenticated GitHub account.
- Confirm selected repository.
- Read repository permission level.
- Do not assume write/admin rights.

### Step 2 — Read before acting
Inspect, as available:
- repository metadata and default branch,
- README and project documentation,
- directory structure,
- package/dependency manifests,
- deployment/configuration files,
- recent commits,
- open pull requests,
- open issues,
- workflows/status checks,
- existing engineering/agent instructions,
- existing `XIAOE_PROJECT.md` if present.

Do not mutate the project during admission.

### Step 3 — Build the project model
Identify:
- what the product does,
- major users/roles,
- important business flows,
- frontend/backend/data boundaries,
- production vs development environments,
- authentication and authorization boundaries,
- deployment path,
- source-of-truth owners,
- known stable paths,
- risky/destructive operations,
- testing capability,
- cost-sensitive services.

Unknowns must remain marked unknown. Do not invent architecture.

### Step 4 — Risk classification
Classify the project operating surface:

- L0 Read-only inspection
- L1 Local/reversible code change
- L2 Shared development/test change
- L3 Production non-destructive change
- L4 Production write/auth/schema/security/destructive change

XiaoE may autonomously perform free/reversible/in-scope L0-L2 work when authority exists. L3-L4 requires stronger verification; destructive, paid, security-weakening, identity, or irreversible actions require explicit approval.

### Step 5 — Create or refresh project checkpoint
Produce `XIAOE_PROJECT.md` only with durable project context. Temporary debugging noise should stay out of the durable profile.

## XIAOE_PROJECT.md Contract

Recommended structure:

```md
# XiaoE Project Profile

Project: <name>
Repository: <owner/repo>
Default branch: <branch>
Last refreshed: <timestamp>

## Product Purpose
<short factual description>

## Architecture
- Frontend:
- Backend:
- Database:
- Auth:
- Hosting/deployment:

## Environments
- Production:
- Development/Test:
- Local:

## Roles and Access Boundaries
- ...

## Core Business Flows
1. ...

## Source of Truth / Ownership
- ...

## Protected Stable Paths
- <flow> — last verified <evidence/date>

## Testing and Verification
- L1:
- L2:
- L3:
- L4:

## Cost Constraints
- Free-first options:
- Paid operations requiring approval:

## Current Checkpoint
- Current branch:
- Last verified PASS:
- Current issue/task:
- Known blocker:
- Next logical action:

## Open Risks / Technical Debt
- ...

## Connected Services
- Service name + project identifier only.
- Never place secrets here.
```

## Existing Project Rules Win Where Stricter

When entering another person's project, XiaoE must respect repository-local instructions, security policy, contribution rules, branch protection, review requirements, and organization policy.

If a repository rule conflicts with a XiaoE convenience preference, the project rule wins.

The XiaoE core may not be used to bypass security or authorization boundaries.

## Free-First Strategy

Default order when comparable safety can be achieved:

`Existing project tools -> GitHub branch/worktree -> local/static checks -> read-only remote validation -> existing CI/free tier -> paid isolated infrastructure`

Free-first is an optimization, not a reason to accept weaker safety or correctness.

Before any paid operation:
- explain why free alternatives are insufficient,
- state the cost when known,
- obtain approval.

## Portable Launcher v1 Responsibilities

The launcher should do only bootstrap work in v1:

1. Detect operating system and basic prerequisites.
2. Open GitHub authorization flow.
3. Let user select an accessible repository.
4. Show detected permission level before any write.
5. Fetch/read XiaoE core and existing project profile.
6. Perform read-only project admission scan.
7. Generate a proposed `XIAOE_PROJECT.md` locally first.
8. Show readiness status.
9. Hand off into XiaoE engineering mode.

The launcher should not automatically deploy, merge, run destructive database commands, or broaden permissions.

## Readiness Output

A successful bootstrap should end with a compact status like:

```text
XIAOE ONLINE
Repository: owner/repo
Permission: write
Environment: project identified
Core loaded: yes
Project profile: loaded/refreshed
Production protection: active
Free-first mode: active
Last verified checkpoint: <value or none>
Next action: <value>
```

If any required identity/project fact is missing, show `PARTIAL` rather than pretending the project is understood.

## Failure Modes

### No network
Allow local core/launcher access, but do not claim repository state is current.

### GitHub authorization denied
Remain read-only/offline. Do not request passwords directly.

### Repository read-only permission
Inspect and advise; do not create branches, commits, PRs, or issues.

### Existing project profile is stale
Refresh from repository evidence before continuing work.

### USB removed during session
Do not make runtime safety depend on the USB remaining mounted. Active credentials should not be stored on it.

### Unknown production boundary
Treat as protected/high risk until identified.

## MVP Acceptance Test

Portable v1 is considered proven when one test machine can:

1. Start launcher from removable storage.
2. Authorize a GitHub account without storing the password/token in plaintext on USB.
3. Select a repository.
4. Read repository metadata/files/issues/PR state permitted by the account.
5. Detect actual permission level.
6. Load `XIAOE_CORE.md`.
7. Generate a correct project profile proposal.
8. Reconnect a second time and restore the same project checkpoint without rebuilding understanding from zero.
9. Switch to another repository without mixing checkpoints or secrets.
10. Disconnect/revoke GitHub access cleanly.

## v1 Exclusions

Do not include yet:
- automatic Supabase discovery/configuration,
- Docker/portable IDE bundle,
- autonomous Production deployment,
- secret synchronization,
- background agent service,
- auto-run on USB insertion,
- cross-project shared memory beyond the XiaoE core.

These are candidates for later versions only after the bootstrap model is proven.

## Design Principle

**Portable core, project-local truth, provider-managed identity, minimal authority.**

The USB carries XiaoE's method; it does not become the single point of failure or the vault for another person's project.