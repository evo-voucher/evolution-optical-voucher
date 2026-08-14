-- Non-destructive Admin control-directory contract checks.
-- Run only after migrations on the verified NEW Supabase target.

with required_functions(signature) as (
  values
    ('admin_partner_directory()'),
    ('admin_active_branches()'),
    ('admin_set_partner_status(uuid,text)'),
    ('admin_set_partner_voucher_limit(uuid,integer)'),
    ('admin_set_partner_staff_limit(uuid,integer)'),
    ('admin_get_partner_claim_access(uuid)'),
    ('admin_set_partner_claim_access(uuid,boolean,text[])')
)
select r.signature as missing_function
from required_functions r
where to_regprocedure('public.' || r.signature) is null;

-- Expected: zero rows.

select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig, ','),'') as proconfig
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_partner_directory','admin_active_branches',
    'admin_set_partner_status','admin_set_partner_voucher_limit',
    'admin_set_partner_staff_limit','admin_get_partner_claim_access',
    'admin_set_partner_claim_access'
  )
order by p.proname;

-- Review expectations:
-- 1) all rows use SECURITY DEFINER;
-- 2) search_path is pinned to public;
-- 3) anon has no EXECUTE on these functions;
-- 4) authenticated has EXECUTE only because each function performs its own Admin check.

select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_partner_directory','admin_active_branches',
    'admin_set_partner_status','admin_set_partner_voucher_limit',
    'admin_set_partner_staff_limit','admin_get_partner_claim_access',
    'admin_set_partner_claim_access'
  )
order by p.proname;

-- Expected: anon_execute=false; authenticated_execute=true for each listed function.
