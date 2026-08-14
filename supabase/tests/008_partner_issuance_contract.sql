-- Non-destructive Partner issuance contract checks.
-- Run only after migrations on the verified NEW Supabase target.

-- Required Partner issuance functions must exist.
with required_functions(signature) as (
  values
    ('partner_issuable_voucher_catalog()'),
    ('issue_engine_voucher(uuid,text,text)')
)
select r.signature as missing_function
from required_functions r
where to_regprocedure('public.' || r.signature) is null;

-- Expected: zero rows.

-- Execution boundary: authenticated only; never anon.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig, ','),'') as proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('partner_issuable_voucher_catalog','issue_engine_voucher')
order by p.proname;

-- Expected:
-- security_definer=true, search_path pinned to public,
-- anon_execute=false, authenticated_execute=true.

-- Tenant-binding source contract: issue_engine_voucher must derive Partner from auth identity.
select p.proname,
       position('auth.uid()' in pg_get_functiondef(p.oid))>0 as derives_auth_identity,
       position('partner_users' in pg_get_functiondef(p.oid))>0 as resolves_partner_membership,
       position('p_partner_id' in pg_get_functiondef(p.oid))=0 as no_partner_id_input_contract
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='issue_engine_voucher'
  and pg_get_function_identity_arguments(p.oid)='p_version_id uuid, p_customer_name text, p_customer_phone text';

-- Runtime checks still required with real Auth users:
-- A) Partner A can issue only a Version returned by its own catalog.
-- B) Partner A cannot issue a Version allocated only to Partner B.
-- C) suspended Partner / removed Partner user / disabled Partner Staff is rejected.
-- D) exhausted allocation or supply is rejected atomically.
-- E) resulting voucher.partner_id equals the authenticated Partner tenant.
-- F) returned public_token opens only the public Voucher view; QR payload remains voucher_code.
