# Health Advisor Baseline

Status date: 2026-09-02

## Purpose

Record the current reviewed Supabase security/performance advisor baseline for voucher-stage and hosted Production so future health checks can focus on newly introduced warnings instead of repeatedly re-auditing known intentional items.

## Security baseline

### RLS enabled with no policy

The following tables are intentionally reviewed as RLS-enabled with no direct client policy at this time:

- `admin_bootstrap_config`
- `admin_notification_reads`
- `customer_districts`
- `operational_identity_realms`
- `partner_code_counters`
- `partner_customers`
- `system_customer_field_settings`

Interpretation: RLS enabled with no policy is not automatically a defect. For these tables, direct client access is intentionally denied unless mediated through controlled functions/service paths. Revisit only if the access model changes.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

### `get_public_voucher(uuid)` anon SECURITY DEFINER warning

This RPC intentionally remains callable by `anon` because it is the public voucher lookup surface. Do not revoke `anon` merely to clear the advisor warning. Any future change should preserve public voucher access semantics while reviewing data minimization and token safety.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable

### Authenticated SECURITY DEFINER warnings

Supabase reports many authenticated-callable SECURITY DEFINER functions. These were reviewed as an authorization-surface warning class rather than an automatic vulnerability.

Observed authorization patterns include:

- Admin RPCs validating an active Admin identity, commonly through `is_voucher_admin()` or direct active `admin_users` checks.
- Partner RPCs resolving or asserting Partner context through `resolve_partner_portal_context()`, `current_partner_id()`, or partner-user membership checks.
- Staff RPCs resolving Staff/Admin context through `resolve_staff_portal_context()`.
- `customer_district_options()` and `customer_field_requirements()` requiring authenticated operational realm `partner` or `admin`.
- `partner_set_staff_access(boolean)` requiring an active `partner_admin` in the caller's own Partner tenant.
- `partner_staff_capacity()` scoping results to the caller's active Partner Admin membership.
- `admin_next_partner_code(text)` and `admin_preview_partner_code(text)` directly requiring `auth.uid()` to map to an active Admin.
- `issue_engine_voucher_with_customer(...)` delegating authorization to the underlying issuance engine instead of duplicating the guard.

Decision: do not bulk revoke authenticated EXECUTE or convert these functions merely to eliminate advisor noise. Re-open only when a specific function lacks a valid internal authorization boundary or when the application exposure model changes.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

### Production Auth leaked-password protection

Hosted Production currently reports `Leaked Password Protection Disabled`.

This is a real security-hardening opportunity because it is independent of Voucher database behavior. It should be enabled through Supabase Auth configuration when operationally approved. No database migration is required.

Reference: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Performance baseline

### Unindexed foreign keys

Advisor INFO notices remain for several foreign keys. These do not require immediate blanket indexing.

Higher-value candidates to observe as real traffic grows include relationships around:

- `redemptions(voucher_id, partner_id)`
- `vouchers(allocation_id, partner_id)`
- `partner_voucher_allocations(version_id)`
- `voucher_allocation_events(allocation_id, partner_id, version_id)`
- `admin_audit_log(partner_id)`

Decision: add indexes only when query plans, workload, latency, lock behavior, or production data scale justify them. Avoid adding every advisor-suggested index by default.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

### Unused indexes

Do not drop indexes solely because Stage reports them unused. Stage has low/limited realistic traffic, so its index-usage statistics are not representative of Production demand. Production also reports a smaller subset of unused indexes.

Decision: index removal requires Production evidence, workload review, dependency review, and a rollback-safe migration.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Operational rule for future health checks

1. Re-run Supabase security and performance advisors after meaningful DDL/security changes.
2. Compare against this baseline.
3. Treat only new warnings, changed severity, changed exposure, or newly unsupported assumptions as fresh work.
4. Do not mutate Stage or Production merely to make the advisor list empty.
5. Production remains read-only unless an explicit production-change decision is made.

## Current health conclusion

- No immediate database-structure security red flag identified.
- Current RLS/no-policy findings are explainable under the existing controlled-RPC design.
- SECURITY DEFINER warnings were reviewed as authorization-surface warnings and not blanket vulnerabilities.
- No performance migration is currently justified solely from advisor INFO notices.
- Production leaked-password protection remains the clearest independent security-hardening action.
