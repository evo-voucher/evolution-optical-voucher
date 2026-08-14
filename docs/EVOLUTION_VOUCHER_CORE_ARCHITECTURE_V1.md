# Evolution Voucher Core Architecture v1

Status: Foundation specification before database rebuild
Principle: Root before flower

## 1. Purpose
Evolution Voucher is a controlled voucher issuance and redemption system for Evolution Optical and external partners. The system must remain understandable, auditable, recoverable, and safe before UI expansion.

The system is not defined by the current HTML. The source of truth is the business model below. Existing GitHub pages and any previous Supabase schema are evidence/reference only.

## 2. Core business chain

Admin -> Partner -> Partner User/Staff -> Voucher -> Allowed Branch -> Redemption -> Audit Record

Every write must be attributable to an authenticated actor. Every voucher must have one canonical lifecycle. Redemption must be atomic and non-repeatable.

## 3. Roles

### Admin
- Creates, updates, suspends and reactivates partners.
- Sets voucher allocation/limit rules.
- Controls partner claim branches.
- Controls partner staff allowance.
- Manages Evolution branches and redemption staff.
- Can inspect vouchers, redemptions and audit history.
- Can correct configuration, but must not silently rewrite historical redemption records.

### Partner Admin
- Belongs to exactly one partner.
- Can issue vouchers within the partner's remaining allocation.
- Can manage partner staff only within limits configured by Admin.
- Can view only the partner's own vouchers and related redemption status.
- Loses operational access when the partner is suspended.

### Partner Staff
- Belongs to exactly one partner.
- Can issue vouchers only when enabled by the partner/admin policy.
- Cannot alter partner-level limits or claim rules.
- Historical actions remain preserved after staff suspension/deletion.

### Evolution Staff / Branch Staff
- Belongs to one branch unless granted an explicit all-branch manager role.
- Can redeem only vouchers valid for the staff member's permitted branch scope.
- Cannot alter voucher ownership, allocation or historical redemption facts.

### All-Branch Manager
- Can manage branch staff according to Admin policy.
- Can redeem across approved branches.
- Is still subject to audit logging and cannot erase history.

## 4. Core entities

### partners
Canonical partner/company record.
Key concepts:
- partner_code unique and immutable after issuance unless a controlled migration is performed
- partner_name
- status: active | suspended
- voucher_limit / allocation policy
- staff_limit
- created_at / updated_at

### partner_users
Authenticated users linked to partners.
Key concepts:
- user_id -> auth.users
- partner_id
- role: partner_admin | partner_staff
- status: active | suspended
- display name

### branches
Evolution redemption locations.
Key concepts:
- branch_code unique
- branch_name
- address
- status

### staff_users
Evolution operational staff.
Key concepts:
- user_id -> auth.users
- branch_id nullable only for an explicit all-branch role
- role: staff | manager | all_branch_manager
- status

### vouchers
One row represents one issued voucher.
Key concepts:
- voucher_code unique and immutable
- partner_id
- issued_by_user_id
- customer_name
- customer_phone
- voucher_type / face value
- issued_at
- expiry_date
- status: issued | redeemed | expired | cancelled
- redeemed_at is derived/controlled by redemption transaction, not freely editable

No customer IC/passport field is required.

### voucher_branches
Voucher-specific allowed branch mapping when the voucher is not valid at all branches.

### partner_claim_settings / partner_claim_branches
Partner-level default claim eligibility configured by Admin. These defaults govern future issuance, while the issued voucher should preserve the effective rule needed for historical correctness.

### redemptions
Immutable business event for a successful redemption.
Key concepts:
- voucher_id unique for successful redemption
- voucher_code snapshot/reference
- branch_id
- redeemed_by_user_id
- redeemed_at
- partner_id
- optional operational note

A voucher must never have two successful redemption records.

### admin_audit_log / audit events
Append-only record of high-impact configuration changes such as partner suspension, branch changes, voucher allocation changes and staff access changes.

## 5. Voucher lifecycle

Canonical state machine:

issued -> redeemed
issued -> expired
issued -> cancelled

Rules:
- redeemed is terminal.
- expired is terminal unless an Admin performs an explicit controlled reissue/new voucher; do not mutate history to pretend the old voucher never expired.
- cancelled is terminal.
- UI labels never decide state; database rules decide state.

## 6. Voucher issuance transaction

Issuance must be performed as one trusted database operation, not as a sequence of loosely related browser writes.

Required checks:
1. Authenticated user exists and is active.
2. User belongs to the stated partner.
3. Partner is active.
4. User role is allowed to issue.
5. Partner allocation has remaining capacity.
6. Voucher code is generated/validated uniquely.
7. Effective claim branches are captured.
8. Voucher is inserted.
9. Allocation/usage counters are updated consistently.
10. Issuance event is logged.

If any step fails, the whole operation must fail without partial data.

## 7. Redemption transaction

Redemption is the highest-integrity operation in the system and must be server/database controlled.

Required checks in one atomic transaction:
1. Authenticated Evolution staff is active.
2. Staff branch scope is valid.
3. Voucher exists.
4. Voucher status is issued.
5. Voucher is not expired.
6. Partner is valid according to policy.
7. Current branch is allowed for that voucher.
8. No successful redemption already exists.
9. Insert redemption record.
10. Change voucher state to redeemed and set redeemed_at.
11. Commit both changes together.

Concurrent scans of the same QR must result in exactly one success and all later attempts returning ALREADY_REDEEMED.

## 8. RLS and security rules

General rule: browser code is untrusted. A hidden button is not security.

- Admin-only configuration must be protected by database policy/function checks.
- Partner users can read only their own partner scope.
- Partner users cannot spoof partner_id on insert/update.
- Evolution staff can read voucher data necessary for redemption but cannot browse unrelated private partner data unless explicitly required.
- Sensitive writes should use narrowly scoped RPC/functions rather than broad table UPDATE permission.
- service_role keys must never exist in GitHub Pages/browser JavaScript.
- Public anon/publishable key is acceptable only with correct RLS.
- Historical redemption/audit rows should be append-only to ordinary users.

## 9. Data integrity constraints

Minimum database constraints:
- unique(partners.partner_code)
- unique(branches.branch_code)
- unique(vouchers.voucher_code)
- unique successful redemption per voucher (prefer unique voucher_id in redemptions)
- foreign keys between users/partners/vouchers/branches/redemptions
- check constraints for role/status enums where practical
- NOT NULL on core ownership and timestamp fields
- indexes on voucher_code, partner_id, status, expiry_date, redeemed_at, branch_id

Counters such as vouchers_issued must never be the sole source of truth. They may be cached/derived, but the voucher rows and allocation events remain authoritative.

## 10. UI modules

The existing front-end can be retained as a UX reference, but modules should map cleanly to business capabilities:

- Main / Login
- Admin Portal
- Partner Portal
- Staff Redemption Portal
- Public Voucher View
- Voucher QR Share
- Branch Management
- Partner Management
- Partner Staff Management
- Evolution Staff Management
- Voucher Reports
- Redemption Records

UI must display database truth; it must not maintain a second independent business state in localStorage.

## 11. Recovery and backup model

Three layers:
1. GitHub: front-end source, SQL migrations, architecture docs.
2. Supabase schema migrations: tables, functions, triggers, RLS, constraints.
3. Business-data export/dump: partners, vouchers, redemptions, branches and user mappings.

Before every high-impact database migration:
- capture current schema/version
- export critical business data when applicable
- record migration in GitHub
- verify rollback/recovery path

## 12. Rebuild phases

### Phase 0 - Freeze and observe
- No destructive change to any old production database.
- Inventory GitHub pages and current database objects.
- Identify which Supabase project is the new empty target.

### Phase 1 - Foundation
- Create canonical tables and constraints.
- Add auth-to-role mapping.
- Add RLS.
- Add audit foundation.

### Phase 2 - Trusted operations
- Implement atomic voucher issuance RPC/function.
- Implement atomic redemption RPC/function.
- Implement partner/staff administration functions where direct table writes are too broad.

### Phase 3 - Front-end wiring
- Point Admin, Partner, Staff and Voucher pages to the new target project.
- Remove obsolete/duplicate database write paths.
- Keep one source of truth for each operation.

### Phase 4 - Verification
- Role matrix tests.
- Suspended partner tests.
- Branch restriction tests.
- Allocation limit tests.
- Double-redemption concurrency test.
- Expired voucher test.
- Audit record test.
- Mobile/PWA regression test.

### Phase 5 - Cutover
- Backup old production state.
- Seed/migrate required records.
- Switch GitHub Pages configuration to the new backend.
- Run smoke tests before commercial traffic.

## 13. Non-negotiable invariants

1. One voucher code = one voucher identity.
2. One voucher = at most one successful redemption.
3. Partner data cannot cross partner boundaries.
4. Suspended users/partners cannot continue operational writes.
5. Branch restrictions are enforced by database logic, not only UI.
6. Historical redemption events are not silently rewritten.
7. Every privileged mutation is attributable to an authenticated actor.
8. No service-role secret in client-side code.
9. Database migrations are versioned in GitHub.
10. No patch is accepted if it weakens the root model for a short-term UI fix.

## 14. Current implementation posture

The repository currently contains separate Admin, Partner, Staff and Voucher front-end pages and PWA assets. These are retained as reference during the rebuild, not treated as the database specification.

The next technical action is to identify the exact empty Supabase target project, then build Phase 1 there from versioned migrations rather than editing an unknown production database directly.
