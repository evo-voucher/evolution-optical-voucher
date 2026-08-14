-- Security boundary audit v1
-- Non-destructive verification for a NEW reconstructed Evolution Voucher Supabase target.
-- Run after all migrations. Any returned row in the FAIL sections requires review.

-- A. SECURITY DEFINER functions in public schema must pin search_path.
-- Expected: zero rows.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  p.proconfig
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.prosecdef
  and not exists (
    select 1
    from unnest(coalesce(p.proconfig,'{}'::text[])) cfg
    where cfg like 'search_path=%'
  )
order by p.proname;

-- B. Sensitive tenant tables must have RLS enabled.
-- Expected: zero rows.
with required(table_name) as (
  values
    ('partners'),
    ('partner_users'),
    ('partner_claim_settings'),
    ('partner_claim_branches'),
    ('vouchers'),
    ('voucher_branches'),
    ('redemptions'),
    ('partner_voucher_access'),
    ('partner_voucher_allocations'),
    ('voucher_allocation_events'),
    ('admin_audit_log'),
    ('admin_users')
)
select r.table_name
from required r
left join pg_class c on c.relname=r.table_name
left join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
where c.oid is null or not c.relrowsecurity
order by r.table_name;

-- C. anon must not have direct table privileges on private business tables.
-- Expected: zero rows.
select table_name, privilege_type
from information_schema.role_table_grants
where grantee='anon'
  and table_schema='public'
  and table_name in (
    'partners','partner_users','staff_users',
    'partner_claim_settings','partner_claim_branches',
    'vouchers','voucher_branches','redemptions',
    'admin_users','admin_audit_log',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events',
    'voucher_templates','voucher_versions','voucher_version_branches','voucher_rules'
  )
order by table_name,privilege_type;

-- D. Only the explicit customer-facing public RPC may be executable by anon.
-- Expected result: get_public_voucher(uuid) only.
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and has_function_privilege('anon',p.oid,'EXECUTE')
order by p.proname,arguments;

-- E. Public customer RPC contract must exist exactly once.
-- Expected count: 1.
select count(*) as public_voucher_rpc_count
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='get_public_voucher'
  and pg_get_function_identity_arguments(p.oid)='p_token uuid';

-- F. Identity realm guards must exist.
-- Expected: three rows, one per realm table.
select event_object_table as table_name, trigger_name
from information_schema.triggers
where trigger_schema='public'
  and trigger_name in (
    'admin_users_guard_identity_realm',
    'partner_users_guard_identity_realm',
    'staff_users_guard_identity_realm'
  )
order by event_object_table;

-- G. Partner consistency guards must exist.
-- Expected: voucher + redemption guard triggers.
select event_object_table as table_name, trigger_name
from information_schema.triggers
where trigger_schema='public'
  and trigger_name in (
    'vouchers_guard_partner_consistency',
    'redemptions_guard_partner_consistency'
  )
order by event_object_table;

-- H. Critical browser-facing mutation tables must not expose INSERT/UPDATE/DELETE
-- directly to authenticated. Mutations are RPC / Edge Function boundaries.
-- Expected: zero rows.
select table_name,privilege_type
from information_schema.role_table_grants
where grantee='authenticated'
  and table_schema='public'
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
  and table_name in (
    'partners','partner_users','staff_users',
    'partner_claim_settings','partner_claim_branches',
    'vouchers','voucher_branches','redemptions',
    'admin_users','admin_audit_log',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events',
    'voucher_templates','voucher_versions','voucher_version_branches','voucher_rules'
  )
order by table_name,privilege_type;

-- I. Review all SECURITY DEFINER functions and their EXECUTE grantees.
-- Informational inventory; use this to spot accidental PUBLIC/anon exposure.
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  coalesce(array_to_string(p.proacl,','),'DEFAULT') as acl
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.prosecdef
order by p.proname,arguments;
