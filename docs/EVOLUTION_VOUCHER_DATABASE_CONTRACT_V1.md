# Evolution Voucher — Database Contract v1

Status: DESIGN LOCK CANDIDATE (read-only analysis complete; not yet applied to any new Supabase project)

## 1. Purpose

This contract defines the database root for the Evolution Voucher system. The frontend may change, voucher products may change, and additional modules may be added, but the core data model must remain stable.

Design rule: **Root before flower**.

The database owns truth for identity, authorization, issuance, redemption, branch scope, limits, and history. The frontend is never allowed to be the final authority for these rules.

---

## 2. Core domain graph

Admin
→ Partner
→ Partner User
→ Voucher
→ Branch Scope
→ Redemption
→ Audit / immutable history

Evolution Optical Staff is a separate operational identity domain from Partner Users.

---

## 3. Layering

### Layer A — Stable Core
Must remain small and durable:

1. `partners`
2. `partner_users`
3. `staff_users`
4. `branches`
5. `vouchers`
6. `voucher_branches`
7. `redemptions`
8. `admin_audit_log`

### Layer B — Policy
Rules that can change without corrupting core history:

1. `partner_claim_settings`
2. `partner_claim_branches`
3. partner staff access / capacity settings

### Layer C — Voucher Engine
Optional / extensible product layer:

1. `voucher_templates`
2. `voucher_versions`
3. `voucher_rules`
4. `voucher_version_branches`
5. `partner_voucher_access`
6. `partner_voucher_allocations`
7. `voucher_allocation_events`

The engine may define what can be issued, but once a voucher is issued the voucher row must contain enough immutable snapshot data to survive future template/version edits.

---

## 4. Stable Core contract

### 4.1 `partners`

Required fields:

- `id uuid primary key`
- `partner_code text unique not null`
- `partner_name text not null`
- `status text not null` — allowed: `active`, `suspended`, `archived`
- `voucher_limit integer not null default 0`
- `staff_limit integer not null default 0`
- `staff_access_enabled boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Optional business fields:

- `contact_person text`
- `contact_phone text`

Rules:

- `partner_code` is immutable after production use unless an explicit admin migration changes it.
- Suspended partner cannot issue vouchers and its partner users cannot perform issue actions.
- Do not trust a cached `vouchers_issued` counter as the only source of truth. If retained for speed, it is derived/cached data and must be transactionally maintained.

---

### 4.2 `partner_users`

Required fields:

- `id uuid primary key`
- `user_id uuid unique not null` → `auth.users(id)`
- `partner_id uuid not null` → `partners(id)`
- `role text not null` — allowed: `partner_admin`, `partner_staff`
- `status text not null` — allowed: `active`, `suspended`, `removed`
- `staff_name text`
- `login_email text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- `removed_at timestamptz`

Rules:

- One Auth user belongs to only one active Partner identity in this system unless multi-partner support is deliberately introduced later.
- `removed` is preferred over hard delete after business activity exists.
- Partner admin may manage only users in its own partner and only within `staff_limit`.
- Disabling `staff_access_enabled` blocks partner staff operations but does not erase staff identities or history.

---

### 4.3 `staff_users`

Evolution Optical redemption staff are separate from Partner staff.

Required fields:

- `id uuid primary key`
- `user_id uuid unique not null` → `auth.users(id)`
- `staff_name text not null`
- `role text not null`
- `status text not null`
- `branch_id uuid null` → `branches(id)`
- `created_at timestamptz not null default now()`

Initial roles:

- `staff`
- `manager`
- `all_branch_manager`
- `admin` only if intentionally represented here; otherwise keep admin identity separate

Rules:

- Branch staff can redeem only within assigned scope.
- All-branch manager may act across branches.
- Deactivated staff cannot redeem.
- Historical redemptions keep a staff name snapshot even if the user is later renamed or removed.

---

### 4.4 `branches`

Required fields:

- `id uuid primary key`
- `branch_code text unique not null`
- `branch_name text not null`
- `address text`
- `phone text`
- `status text not null default 'active'`
- `created_at timestamptz not null default now()`

Rules:

- `branch_code` is stable and machine-facing.
- Disabled/closed branch cannot perform new redemptions but stays in history.

---

### 4.5 `vouchers`

This is the issued voucher record, not the template definition.

Required fields:

- `id uuid primary key`
- `voucher_code text unique not null`
- `public_token uuid unique not null`
- `partner_id uuid not null` → `partners(id)`
- `customer_name text not null`
- `customer_phone text`
- `voucher_type text not null`
- `status text not null`
- `expiry_date date not null`
- `issued_at timestamptz not null default now()`
- `activated_at timestamptz not null default now()`
- `issued_by_user_id uuid`
- `issued_by_name text`
- `all_branches boolean not null default false`
- `usage_limit integer not null default 1`
- `usage_count integer not null default 0`
- `metadata jsonb not null default '{}'::jsonb`
- `template_id uuid null`
- `version_id uuid null`
- `allocation_id uuid null`
- `revoked_at timestamptz`
- `revoked_by_user_id uuid`
- `revoke_reason text`

Explicitly removed from new design:

- `customer_ic` — no longer required and should not be rebuilt.

Status model:

- `active`
- `redeemed`
- `expired`
- `revoked`

Rules:

- Partner cannot directly INSERT a voucher row from browser code. Voucher issuance goes through one controlled database function / transaction.
- `voucher_code`, `partner_id`, `issued_at`, `issued_by_*`, product snapshot, and branch entitlement are immutable after issue except through explicit admin recovery procedures.
- For single-use vouchers, database constraint/transaction logic must make double redemption impossible under concurrency.
- A voucher cannot be considered valid solely because `status='active'`; expiry, revocation, usage limit, partner state, and branch entitlement must all be evaluated server-side.

---

### 4.6 `voucher_branches`

Used only when `vouchers.all_branches = false`.

Required fields:

- `voucher_id uuid not null` → `vouchers(id)`
- `branch_id uuid not null` → `branches(id)`
- `created_at timestamptz not null default now()`

Constraints:

- primary/unique key on (`voucher_id`, `branch_id`)

Rules:

- When `all_branches=true`, no rows are required here.
- Branch entitlement is checked inside verification/redemption transaction, not only in the UI.

---

### 4.7 `redemptions`

This is business history and must be append-oriented.

Required fields:

- `id uuid primary key`
- `voucher_id uuid not null` → `vouchers(id)`
- `partner_id uuid not null` → `partners(id)`
- `branch_id uuid not null` → `branches(id)`
- `staff_user_id uuid not null` → Auth or operational staff identity
- `staff_name_snapshot text not null`
- `redeem_method text not null` — e.g. `qr`, `manual_code`, `admin`
- `status text not null` — `completed`, `reversed`
- `redeemed_at timestamptz not null default now()`
- `notes text`
- `created_at timestamptz not null default now()`
- reversal fields: `reversed_at`, `reversed_by_user_id`, `reversed_by_name`, `reverse_reason`

Rules:

- Normal users never delete a redemption.
- A reversal changes history state; it does not erase the original redemption.
- Single-use voucher must have at most one non-reversed successful redemption at any moment. This must be enforced transactionally and, where practical, with a partial unique index.
- Redemption and voucher state update happen in the same transaction.

---

### 4.8 `admin_audit_log`

All sensitive admin mutations are logged.

Minimum snapshot:

- actor user id/name
- action type
- entity type/id
- partner id when relevant
- before JSON
- after JSON
- metadata JSON
- created_at

Audit rows are append-only for normal application roles.

---

## 5. Policy layer contract

### 5.1 Partner claim access

`partner_claim_settings`
- `partner_id` primary key
- `all_branches boolean not null`
- `updated_at`
- `updated_by`

`partner_claim_branches`
- (`partner_id`, `branch_id`) unique/primary key
- `created_at`

Meaning:

This is the maximum branch scope the Admin permits a Partner's vouchers to use. A Partner cannot issue a voucher for a branch outside this policy.

Voucher-specific branch scope may be equal to or narrower than partner claim access, never broader.

---

## 6. Transaction boundaries

### 6.1 Issue voucher transaction

One controlled RPC should:

1. identify current authenticated Partner user
2. require active user + active Partner
3. enforce partner staff access rules when actor is partner_staff
4. enforce voucher quota/allocation
5. validate requested voucher product/version
6. validate requested branch scope against Partner claim access
7. generate unique voucher code + public token server-side
8. insert voucher
9. insert voucher branch rows when required
10. update allocation/counter atomically if applicable
11. return safe voucher payload

Failure at any step rolls back all changes.

### 6.2 Verify voucher transaction/function

Verification is read-only and must return a normalized result such as:

- valid / invalid
- reason code
- voucher display fields
- permitted branch summary
- current redeemability

It must not expose private database internals.

### 6.3 Redeem voucher transaction

One controlled RPC should:

1. authenticate operational staff
2. ensure staff active and branch authorized
3. lock target voucher row (`FOR UPDATE` or equivalent serialized protection)
4. re-check status, expiry, revocation, usage count, branch entitlement
5. reject already consumed single-use voucher
6. insert redemption record
7. increment voucher usage count
8. mark voucher `redeemed` when usage limit reached
9. commit once

This is the critical anti-double-redeem boundary.

---

## 7. RLS model

RLS must be enabled on all exposed business tables.

Principles:

- `anon`: no direct table reads for private business data.
- Public voucher page uses one intentionally narrow public function keyed by `public_token`; no raw voucher table access.
- `partner_admin`: read own Partner profile/users/vouchers and perform approved management through controlled functions.
- `partner_staff`: only own Partner data and only approved issue actions while staff access is enabled.
- Evolution staff: read/verify/redeem only within operational branch scope.
- Voucher Admin: system-wide business access.

Avoid dozens of overlapping permissive SELECT policies. Prefer one clear policy per role/action pattern or controlled views/functions when logic becomes complex.

Use `(select auth.uid())` in policies where applicable to avoid per-row auth function re-evaluation.

---

## 8. Function security contract

Use `SECURITY DEFINER` only when necessary.

Every SECURITY DEFINER function must:

- set a safe `search_path`
- perform its own role/ownership/branch checks
- expose the minimum required arguments and return fields
- have explicit GRANT/REVOKE rules
- not be executable by `anon` unless intentionally designed as a public API
- never trust caller-supplied partner/user identity when it can be derived from `auth.uid()`

Trigger helper functions should not be directly executable through the API.

---

## 9. Index contract

Create indexes for actual access paths, especially:

- `partner_users(user_id)` unique
- `partner_users(partner_id, status)`
- `staff_users(user_id)` unique
- `staff_users(branch_id, status)`
- `vouchers(voucher_code)` unique
- `vouchers(public_token)` unique
- `vouchers(partner_id, issued_at desc)`
- `vouchers(status, expiry_date)` where reporting requires it
- `voucher_branches(voucher_id, branch_id)` unique
- `voucher_branches(branch_id)` if branch lookup is used
- `redemptions(voucher_id)`
- `redemptions(partner_id, redeemed_at desc)`
- `redemptions(branch_id, redeemed_at desc)`
- `redemptions(staff_user_id, redeemed_at desc)`

Do not copy every old index blindly; old unused indexes are evidence, not requirements.

---

## 10. Legacy findings that must NOT be copied blindly

1. Legacy core and later multi-voucher engine are mixed in the same database.
2. `customer_ic` still exists in legacy schema even though the product no longer needs it.
3. Multiple overlapping permissive RLS policies exist on several core tables.
4. Several SECURITY DEFINER functions are broadly executable; the new system must use tighter grants and explicit role checks.
5. Legacy database contains additional XiaoE/CRM/system-health modules. These are not part of Voucher Core and must not be brought into a clean voucher database unless deliberately selected.
6. Some indexes in the old system are reported unused. New indexes should follow actual query paths rather than legacy accumulation.

---

## 11. Migration rule

No production database change is allowed without:

1. a versioned SQL migration committed to GitHub
2. a written purpose and rollback/recovery note
3. pre-change backup/export when modifying live data
4. post-migration schema/security check
5. frontend compatibility check

The new blank Supabase project should be built from migrations, never from undocumented manual clicks.

---

## 12. Phase plan

### Phase 1 — Core schema
Partners, users, branches, vouchers, voucher branches, redemptions, audit.

### Phase 2 — RLS + identity helpers
Minimal helper functions, strict grants, role scope.

### Phase 3 — Atomic RPCs
Issue, verify, redeem, reverse.

### Phase 4 — Seed + smoke tests
Create one branch, one Partner, one staff, issue/redeem/reject-double-redeem.

### Phase 5 — Frontend adapter
Point existing Admin/Partner/Staff/Voucher pages to the new contract. Do not redesign UI at this stage.

### Phase 6 — Voucher Engine
Templates, versions, rules, allocations only after the single-voucher core is stable.

---

## 13. Definition of ready-for-live

The database is not considered live-ready until all of these pass:

- partner isolation test
- suspended partner test
- staff scope test
- staff disabled test
- quota test
- invalid branch test
- expiry test
- revoked voucher test
- QR/manual verification test
- concurrent double-redeem test
- redemption record visibility test
- reversal audit test
- anon data exposure test
- service-role key absent from frontend test
- Supabase security advisor review

