# XiaoE Portable Checkpoint

Timestamp: 2026-08-19 02:29 +08:00
Status: Paused / 小E收工
Branch: xiao-e/portable-v1-spec
Production impact: None

## Current State

Portable XiaoE v1 is isolated from `main` and Production.

Implemented on the experimental branch:
- Portable architecture/specification
- `XIAOE_PROJECT` template
- Launcher specification
- Static launcher prototype
- Root Before Flower surfaced as an active highest-priority principle
- Windows PowerShell read-only discovery launcher
- Run/safety documentation

## Core Principles

Highest priority:
- Root Before Flower
- 不补丁｜要根治

Core capabilities:
- 风险判断
- 流程思维
- 根因分析
- 开发隔离

Engineering guardrails:
- 业务定义
- 验证优先
- 可回退
- 上线复核
- 免费优先（only when safety/correctness/isolation are not reduced）

## Last Verified Point

Repository-side files were created successfully on the isolated branch.
No Production or Supabase change was made by Portable work.

Runtime validation of the PowerShell launcher on a second/clean Windows computer has NOT yet been completed.
Real GitHub authorization + repository selection + read-only discovery + checkpoint restore is therefore NOT yet marked PASS.

## Current Blocker / Waiting On

Waiting for a fresh GitHub account / test identity and a suitable machine/session to perform real launcher validation.

## Next Logical Action

When XiaoE comes online again:
1. Confirm the test GitHub account is ready.
2. Keep Portable work on the isolated branch.
3. Run the launcher in a clean Windows environment.
4. Validate GitHub authorization without storing plaintext secrets.
5. Select a repository and run read-only discovery.
6. Confirm checkpoint creation/restoration.
7. Mark PASS only after the complete real path works.
8. Only after that, consider GUI refinement or multi-AI provider adapters.

## Do Not Do Yet

- Do not merge Portable v1 into `main`.
- Do not touch Production/Supabase for Portable testing.
- Do not add paid infrastructure unless free-safe options are insufficient and approval is given.
- Do not build cosmetic GUI features before the real launcher path is validated.

## Resume Trigger

`小E上线`
