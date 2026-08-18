# Run XiaoE Portable v1 (MVP)

This MVP is intentionally **read-only** for first-time GitHub discovery.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- GitHub CLI (`gh`)
- Internet access

## Start

From the `portable` folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-xiaoe.ps1
```

If GitHub CLI is not authenticated, the launcher invokes the official `gh auth login --web` flow. XiaoE does not ask for or store the user's GitHub password.

## What it does

1. Verifies GitHub CLI is available.
2. Verifies/requests GitHub authorization.
3. Lists repositories accessible to the signed-in account.
4. Lets the user choose one repository.
5. Performs bounded read-only discovery of repository metadata, branches, open PRs/issues, recent commits, and important architecture/config paths.
6. Writes a **local non-secret checkpoint** under `portable/state/`.
7. Marks Production boundary as unknown until evidence establishes it.

## What it does NOT do

- no branch creation,
- no repository file write,
- no PR creation,
- no merge,
- no deployment,
- no database write,
- no auth/security setting change,
- no plaintext GitHub token/password storage on the removable drive.

## Root Before Flower

The launcher starts with:

**Root Before Flower — ACTIVE**

First contact with an unfamiliar project is evidence-first. It captures facts before engineering actions are permitted.

## Local checkpoint

The checkpoint contains only operational metadata such as:
- repository identity and URL,
- default branch,
- viewer permission,
- branches,
- open PR/issue metadata,
- recent commit SHAs,
- interesting paths such as README, dependency manifests, workflows, migrations, infra config, and `XIAOE_PROJECT.md`,
- explicit `repository_write_performed=false` and `plaintext_secrets_stored=false` flags.

It does not contain GitHub passwords or access tokens.

## Current limitation

This is the **Windows CLI MVP**, not yet the final graphical USB launcher. Its purpose is to prove the authorization + repository selection + read-only discovery + checkpoint path safely and for free before investing in UI packaging.
