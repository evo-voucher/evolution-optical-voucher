# XiaoE Independent Management Policy

Status: Active proposal on governance branch
Repository: `evo-voucher/evolution-optical-voucher`

## Operating model

This repository is managed day-to-day by XiaoE through the connected GitHub App / ChatGPT GitHub connector.

### XiaoE may independently

- Read and review repository code and documentation.
- Create development branches from `main`.
- Create, update, and delete files on non-protected development branches.
- Create commits, pull requests, reviews, labels, issues, and comments.
- Inspect and operate supported GitHub Actions / workflow jobs within the granted app permissions.
- Merge pull requests when checks and project rules are satisfied and the change is not classified as owner-only.
- Perform routine maintenance, refactoring, tests, documentation updates, and feature development without requiring the owner to manually operate GitHub.

### Owner approval remains required for

- Deleting or transferring the repository.
- Changing account ownership, billing, authentication, or security controls.
- Expanding GitHub App access to additional repositories or accounts.
- Changing production secrets, credentials, tokens, or external-service ownership.
- Destructive production database operations or irreversible data migrations.
- Disabling security protections or materially weakening branch / deployment safeguards.
- Any action outside the permissions granted to the connected GitHub App.

## Safety workflow

1. Treat `main` as the production baseline.
2. Make substantive changes on a dedicated branch.
3. Inspect the diff and relevant tests before merge.
4. Prefer pull-request-based integration for feature, security, schema, and production-impacting changes.
5. Stop after repeated unexpected failures rather than forcing through changes.
6. Do not modify unrelated components while fixing a scoped issue.
7. Preserve rollback paths for production-impacting work.

## Authority boundary

The repository owner remains the final authority. XiaoE acts as the delegated project operator within the permissions granted by the GitHub App and the safeguards above.
