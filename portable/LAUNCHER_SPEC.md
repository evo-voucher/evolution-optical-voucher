# XiaoE Portable v1 — Launcher Specification

Status: Draft on isolated branch
Scope: Portable XiaoE MVP launcher

## Goal

Create a lightweight launcher that can be carried on removable storage and used on another computer to connect to an authorized GitHub account/repository, inspect the project safely, restore project context, and enter XiaoE engineering mode.

The launcher is not the AI model itself. It is the portable bootstrap, policy loader, project selector, and context initializer.

## Core UX

Primary flow:

`Start XiaoE -> Connect GitHub -> Select Repository -> Read-only Discovery -> Build/Load Project Context -> Ready -> 小E上线`

The first session with a repository is discovery-first. Subsequent sessions should prefer restoring the existing project checkpoint, then refreshing only the changed state.

## Screen 1 — Start

Show:
- XiaoE Portable v1
- Core status: loaded / unavailable
- Network status
- GitHub connection status
- Primary action: `Connect GitHub`
- Secondary action: `Open Existing Local Project Context`

No project write is allowed from this screen.

## Screen 2 — GitHub Authorization

Requirements:
- GitHub authentication must be performed by the project owner/user.
- Do not ask XiaoE to receive or store the user's GitHub password.
- Prefer OAuth/GitHub App/device-flow style authorization when implementation permits.
- Request the smallest practical repository scope.
- The user must be able to revoke access independently.

After authorization, show the authenticated account and accessible repositories.

## Screen 3 — Repository Selection

Show repositories available to the authenticated account.

For each selected repository, capture only non-secret metadata needed for discovery:
- owner/repository name
- default branch
- visibility
- permissions granted to the session
- repository URL/identifier

No write operation occurs merely by selecting a repository.

## Screen 4 — Read-only Discovery

On first connection, XiaoE performs a bounded read-only discovery pass.

Typical discovery targets:
- repository metadata
- README / project documentation
- top-level file and directory structure
- dependency manifests and runtime hints
- default branch and active development branches
- recent commits
- open pull requests/issues where useful
- CI/workflow configuration
- deployment/configuration files that contain no secrets
- existing `XIAOE_PROJECT.md`, if present

Discovery rule:

**Unknown project -> Read first -> Map ownership and execution path -> Establish risk boundaries -> Then propose work.**

The launcher must not infer Production boundaries from filenames alone when evidence is weak.

## Screen 5 — Project Context

If `XIAOE_PROJECT.md` exists:
- load it,
- compare it with current repository state,
- mark stale or conflicting assumptions,
- preserve verified stable-path information.

If it does not exist:
- generate a local draft using `XIAOE_PROJECT_TEMPLATE.md`,
- do not commit it automatically,
- let XiaoE use it as session context first.

Committing project context to the repository is a separate reversible action and should occur only when useful and authorized.

## Screen 6 — Ready

Show a compact readiness card:

- Core: loaded
- GitHub: connected
- Repository: selected
- Access: read-only / read-write
- Project context: restored / newly discovered
- Production boundary: known / unknown
- Last verified checkpoint: known / none
- Current risk state: low / requires review

Primary action:

`小E上线`

The launcher may enter engineering mode only after the core and selected project context are available.

## Operating Modes

### Discovery Mode
Default for first-time repositories.

Permissions behavior:
- read-only actions only,
- no branch creation,
- no file changes,
- no deployment,
- no database writes.

### Engineering Mode
Available after discovery establishes enough context.

Engineering actions remain governed by XiaoE Core:
- risk judgment,
- flow thinking,
- root-cause analysis,
- development isolation,
- verification-first,
- rollback readiness,
- free-first when safety is not reduced.

### Recovery Mode
Used when local context is missing/corrupt or the repository state conflicts with the saved checkpoint.

Behavior:
- stop auto-restore,
- refresh repository facts,
- isolate the conflicting assumptions,
- rebuild project context without altering the repository.

## Security Boundaries

Never store in plaintext on removable media:
- GitHub passwords
- long-lived access tokens
- Supabase service-role keys
- private API keys
- database passwords
- full JWTs

Preferred model:
- the owner authorizes access on the active computer,
- credentials remain in OS-secure storage or an ephemeral session where practical,
- removable media stores only non-secret launcher configuration and project checkpoints.

If secure credential storage is unavailable, the launcher should require re-authorization rather than silently downgrade security.

## Free-first Principle

MVP should use free components whenever they provide adequate safety and isolation.

Preferred v1 building blocks:
- static/local launcher UI
- GitHub's available authentication/API path
- local JSON/Markdown context files
- GitHub branches for isolated changes
- repository-native CI where available

Do not add a paid cloud control plane merely to make v1 work.

Free-first never overrides security, correctness, or project-owner consent.

## Failure Behavior

If network is unavailable:
- allow local context viewing,
- do not claim GitHub state is current.

If GitHub authorization fails:
- remain disconnected,
- do not fall back to pasted passwords or insecure credential storage.

If repository discovery is incomplete:
- mark project state as incomplete,
- do not infer sensitive boundaries or deploy.

If project context conflicts with repository evidence:
- repository evidence wins for current code state,
- prior context remains historical evidence only,
- XiaoE should resolve the conflict before engineering work proceeds.

## MVP Success Criteria

Portable v1 is successful when a user can:
1. start XiaoE from removable storage,
2. authorize their own GitHub access,
3. select one repository,
4. complete read-only discovery,
5. create or restore project context,
6. enter `小E上线` mode with a clear access/risk boundary,
7. disconnect without leaving plaintext secrets on the removable drive.

## Explicit Non-goals for v1

Not required in v1:
- local LLM inference on the USB drive,
- automatic Production deployment,
- automatic Supabase ownership transfer,
- Docker/IDE bundles,
- background autonomous agents,
- cross-project secret synchronization,
- forced USB autorun.

These can be considered only after the authorization/context/bootstrap flow is proven stable.
