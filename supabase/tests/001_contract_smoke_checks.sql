-- Evolution Voucher backend contract smoke checks
-- NON-DESTRUCTIVE. Run only after migrations are applied to the NEW target project.
-- This file is intentionally not a migration.

-- 1) Required core tables.
select to_regclass('public.partners') as partners,
       to_regclass('public.partner_users') as partner_users,
       to_regclass('public.staff_users') as staff_users,
       to_regclass('public.operational_identity_realms') as operational_identity_realms,
       to_regclass('public.vouchers') as vouchers,
       to_regclass('public.redemptions') as redemptions,
       to_regclass('public.voucher_templates') as voucher_templates,
       to_regclass('public.voucher_versions') as voucher_versions,
       to_regclass('public.partner_voucher_allocations') as partner_voucher_allocations;

-- 2) Required security / routing / control functions.
select to_regprocedure('public.is_voucher_admin()') as is_voucher_admin,
       to_regprocedure('public.current_partner_id()') as current_partner_id,
       to_regprocedure('public.current_operational_realm()') as current_operational_realm,
       to_regprocedure('public.claim_operational_identity_realm(uuid,text)') as claim_operational_identity_realm,
       to_regprocedure('public.release_operational_identity_realm(uuid,text)') as release_operational_identity_realm,
       to_regprocedure('public.get_public_voucher(uuid)') as get_public_voucher,
       to_regprocedure('public.verify_voucher(text,text)') as verify_voucher,
       to_regprocedure('public.redeem_voucher(text,text,text,text)') as redeem_voucher,
       to_regprocedure('public.staff_operational_context()') as staff_operational_context,
       to_regprocedure('public.staff_recent_redemptions(integer)') as staff_recent_redemptions,
       to_regprocedure('public.staff_today_summary()') as staff_today_summary,
       to_regprocedure('public.get_my_partner_claim_access()') as get_my_partner_claim_access,
       to_regprocedure('public.admin_dashboard_summary()') as admin_dashboard_summary,
       to_regprocedure('public.admin_partner_directory()') as admin_partner_directory,
       to_regprocedure('public.admin_active_branches()') as admin_active_branches,
       to_regprocedure('public.partner_issuable_voucher_catalog()') as partner_issuable_voucher_catalog,
       to_regprocedure('public.admin_engine_allocate(uuid,uuid,integer,uuid)') as admin_engine_allocate,
       to_regprocedure('public.admin_engine_allocate_all(uuid,integer,uuid)') as admin_engine_allocate_all,
       to_regprocedure('public.admin_engine_revoke_unissued(uuid,integer,text,uuid)') as admin_engine_revoke_unissued,
       to_regprocedure('public.admin_engine_retire_version(uuid,text,uuid)') as admin_engine_retire_version;

-- 3) RLS must be enabled on tenant/private tables.
select c.relname,
       c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relname in (
    'partners','partner_users','staff_users','operational_identity_realms',
    'partner_claim_settings','partner_claim_branches',
    'vouchers','redemptions','partner_voucher_access','partner_voucher_allocations',
    'voucher_allocation_events'
  )
order by c.relname;

-- 4) Identity-realm guards must exist.
select tgname,
       tgrelid::regclass as table_name
from pg_trigger
where not tgisinternal
  and tgname in (
    'admin_users_guard_identity_realm',
    'partner_users_guard_identity_realm',
    'staff_users_guard_identity_realm'
  )
order by tgname;

-- 5) Partner consistency guards must exist.
select tgname,
       tgrelid::regclass as table_name
from pg_trigger
where not tgisinternal
  and tgname in (
    'vouchers_guard_partner_consistency',
    'redemptions_guard_partner_consistency'
  )
order by tgname;

-- 6) Public exposure rule: anon should only need explicit public RPC execution;
-- tenant/private tables must not have direct anon table privileges.
select table_name, privilege_type
from information_schema.table_privileges
where table_schema='public'
  and grantee='anon'
  and table_name in (
    'partners','partner_users','staff_users','operational_identity_realms',
    'vouchers','redemptions','partner_voucher_allocations','voucher_allocation_events'
  )
order by table_name, privilege_type;

-- Expected result for section 6: ZERO ROWS.

-- 7) Migration contract note:
-- The authenticated-context behavioral checks (Admin vs Partner A vs Partner B vs Staff)
-- must be executed with real test Auth users after the new target is bound.
-- Required E2E assertions:
--   One Auth UID cannot be concurrently activated in two operational realms.
--   Removed historical Partner membership does not block later re-onboarding.
--   Partner A cannot read Partner B voucher/allocation/redemption rows.
--   Partner B cannot read Partner A rows.
--   Partner catalog shows only active, authorized, allocated Versions with remaining capacity.
--   Staff context exposes only assigned branch, except all_branch_manager which receives active branch choices.
--   Staff verify/redeem/history remain RPC-only and branch-scoped.
--   Admin control directory is available only through Admin RPCs, not browser table reads.
--   Concurrent Admin allocation increments are preserved by 033.
--   allocate_all is all-or-nothing inside one database transaction.
--   Revoke/retire races cannot invalidate already-issued capacity or issue after retirement.
--   Public token lookup reveals no customer phone, auth IDs, allocation IDs or metadata.
--   Issue -> Public -> Verify -> Redeem -> Report -> Reverse preserves audit/history.
