-- Evolution Voucher cutover readiness inventory.
-- NON-DESTRUCTIVE. Run only on the verified NEW Supabase target after all migrations.
-- This test does not prove runtime behavior by itself; it verifies that the expected
-- structural/runtime contracts are present before frontend cutover.

-- 1) Migration-era structural functions expected after 037.
select
  to_regprocedure('public.current_operational_realm()') as current_operational_realm,
  to_regprocedure('public.staff_operational_context()') as staff_operational_context,
  to_regprocedure('public.partner_issuable_voucher_catalog()') as partner_issuable_voucher_catalog,
  to_regprocedure('public.issue_engine_voucher(uuid,text,text)') as issue_engine_voucher,
  to_regprocedure('public.verify_voucher(text,text)') as verify_voucher,
  to_regprocedure('public.redeem_voucher(text,text,text,text)') as redeem_voucher,
  to_regprocedure('public.get_public_voucher(uuid)') as get_public_voucher,
  to_regprocedure('public.reverse_redemption(uuid,text)') as reverse_redemption,
  to_regprocedure('public.guard_partner_global_voucher_quota()') as guard_partner_global_voucher_quota,
  to_regprocedure('public.admin_dashboard_summary()') as admin_dashboard_summary,
  to_regprocedure('public.partner_voucher_summary()') as partner_voucher_summary;

-- 2) Canonical triggers required for tenant, capacity and quota integrity.
select tgname, tgrelid::regclass as table_name
from pg_trigger
where not tgisinternal
  and tgname in (
    'vouchers_guard_partner_consistency',
    'redemptions_guard_partner_consistency',
    'vouchers_guard_engine_capacity',
    'vouchers_guard_global_partner_quota',
    'admin_users_guard_identity_realm',
    'partner_users_guard_identity_realm',
    'staff_users_guard_identity_realm'
  )
order by tgname;

-- 3) Critical private tables must have RLS enabled.
select c.relname, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relname in (
    'partners','partner_users','staff_users','operational_identity_realms',
    'vouchers','voucher_branches','redemptions',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events'
  )
order by c.relname;

-- 4) Browser must not receive direct mutation privileges on critical business tables.
select grantee, table_name, privilege_type
from information_schema.table_privileges
where table_schema='public'
  and grantee in ('anon','authenticated')
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
  and table_name in (
    'partners','partner_users','staff_users','operational_identity_realms',
    'vouchers','voucher_branches','redemptions',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events'
  )
order by grantee,table_name,privilege_type;
-- Expected: ZERO ROWS unless a later explicitly-reviewed architecture change documents otherwise.

-- 5) Anonymous function exposure inventory.
select p.oid::regprocedure as function_signature
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and has_function_privilege('anon',p.oid,'EXECUTE')
order by 1;
-- Expected business RPC exposure: get_public_voucher(uuid) only.
-- Extension/system helper functions, if any, must be reviewed separately rather than ignored.

-- 6) Operational realm registry exists and one-live-Partner partial uniqueness remains.
select to_regclass('public.operational_identity_realms') as operational_identity_realms;
select indexname,indexdef
from pg_indexes
where schemaname='public'
  and tablename='partner_users'
  and indexname='uq_partner_users_live_user';

-- 7) Runtime test acknowledgement.
-- Cutover remains BLOCKED until authenticated E2E fixtures prove:
-- Admin Allocate -> Partner Catalog -> Issue -> Public -> Staff Verify -> Redeem -> Report -> Reverse -> Reconcile,
-- Partner A/B isolation, concurrent quota/supply/allocation protection, double-redeem protection,
-- branch enforcement, realm exclusivity, and public minimum-field privacy.