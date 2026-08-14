# XiaoE Memory Architecture Alignment v1

Status: ACTIVE DESIGN REFERENCE
Date: 2026-08-15

## 1. Source architecture from current XiaoE memory model

The XiaoE long-term memory model has three independent memory sources:

1. XiaoE Memory — Supabase `public.memories`
   - long-term project facts
   - architecture decisions
   - system status
   - verified experience
   - development principles

2. ChatGPT memory
   - user background
   - stable preferences
   - broad personal context
   - not the authoritative project state store

3. Current conversation context
   - short-lived working context
   - useful for immediate reasoning
   - must not be treated as long-term truth by itself

Evidence priority:
Current verified state > XiaoE project memory > ChatGPT memory > current-chat assumptions.

## 2. Three XiaoE core commands

### XiaoE Memory / Read
Purpose: load relevant persistent knowledge before continuing project work.

Expected flow:
- identify current project
- query `public.memories`
- filter by namespace/project/importance
- restore only relevant context
- continue from verified state

### XiaoE Save / Write
Purpose: save conclusions, not raw conversation.

Store:
- long-term decisions
- development rules
- architecture direction
- system state milestones
- proven successful procedures
- important failure lessons

Do not store:
- complete chats
- repeated discussion
- temporary guesses
- large raw code or binaries
- irrelevant context

### XiaoE Finish / State record
Purpose: persist the minimum state required to resume work next time.

Record:
- what was completed
- current verified state
- unresolved issues
- next intended step

## 3. Memory namespaces

Recommended namespaces:
- `global` — durable system-wide rules
- `core` — XiaoE identity and operating principles
- `project` — project-specific memory such as Evolution Voucher
- `experience` — verified success/failure lessons
- `organization` — reserved for future multi-tenant organization memory
- `user` — reserved for future user-specific persistent memory

For Evolution Voucher, the primary namespace is `project` with `project_key = evolution_voucher`.

## 4. Separation of responsibilities

### GitHub
Source of truth for:
- code
- migrations
- Edge Functions
- architecture documents
- version history
- deployment artifacts

### Evolution Voucher Supabase
Source of truth for business transactions:
- Partner
- Partner Staff
- Evolution Staff
- Voucher
- Branch
- Redemption
- Voucher Engine
- business audit records

### XiaoE AI Core Supabase
Source of truth for long-term AI memory:
- `public.memories`
- XiaoE project knowledge
- decisions
- verified development experience
- current development state snapshots

XiaoE memory must not become part of the Voucher transaction dependency chain.
If XiaoE memory is unavailable, Partner issuance and Staff redemption must continue working.

## 5. Relationship to Evolution Voucher reconstruction

The current Voucher reconstruction follows the same core principles shown in the XiaoE architecture:

- Root Before Flower
- Lean Development
- Root Cause Before Patch
- Memory stores conclusions, not process
- Read relevant state before continuing work
- Verify before persisting project state

Voucher backend architecture remains:
Stable Core → Voucher Engine → Application/UI → XiaoE Intelligence

XiaoE sits above the transaction system and may analyze or assist, but does not control the core voucher transaction path.

## 6. Recommended memory schema contract

`public.memories` should support at minimum:
- `id uuid`
- `namespace text`
- `memory_type text`
- `title text`
- `content text`
- `importance integer/numeric`
- `project_key text`
- `organization_id uuid nullable`
- `user_id uuid nullable`
- `source text`
- `tags text[] or jsonb`
- `metadata jsonb`
- `is_active boolean`
- `created_at timestamptz`
- `updated_at timestamptz`

The memory table is a knowledge layer, not a chat archive.

## 7. Development resume protocol

Before future Evolution Voucher work:
1. Verify current GitHub state.
2. Verify current Supabase project identity.
3. Load relevant XiaoE project memory.
4. Compare memory against current verified state.
5. Prefer current verified state when conflicts exist.
6. Execute the smallest correct structural change.
7. Test.
8. Persist only verified conclusions and new project state.

## 8. Current alignment decision

For the current rebuild:
- `evo-voucher/evolution-optical-voucher` = new canonical codebase
- legacy `xiaoe-ai/evolution-optical-voucher` = historical UX/behavior evidence
- legacy `Evolution voucher projects` Supabase = historical/business evidence until cutover
- `XiaoE AI Core` Supabase = long-term XiaoE memory layer
- future blank/new Voucher Supabase = target transactional backend

This separation prevents AI-memory growth from contaminating Voucher transaction architecture and preserves clear rollback boundaries.
