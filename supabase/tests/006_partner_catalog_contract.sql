-- Partner issuable Voucher catalog contract checks.
-- NON-DESTRUCTIVE. Run only after migrations are applied to the verified NEW target.

-- A. Required Partner catalog RPC exists.
select to_regprocedure('public.partner_issuable_voucher_catalog()') as partner_issuable_voucher_catalog;
-- Expected: non-null.

-- B. Security posture: SECURITY DEFINER, pinned search_path, authenticated-only execute.
select
  p.proname,
  p.prosecdef as security_definer,
  coalesce(array_to_string(p.proconfig,','),'') as proconfig,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='partner_issuable_voucher_catalog';
-- Expected: security_definer=true, search_path=public,
-- authenticated_execute=true, anon_execute=false.

-- C. Static source checks for tenant and capacity boundaries.
select
  position('pu.user_id=v_uid' in pg_get_functiondef(p.oid))>0 as derives_identity_from_auth,
  position('pva.partner_id=v_partner_id' in pg_get_functiondef(p.oid))>0 as access_scoped_to_partner,
  position('pa.partner_id=v_partner_id' in pg_get_functiondef(p.oid))>0 as allocation_scoped_to_partner,
  position('remaining_allocation' in pg_get_functiondef(p.oid))>0 as exposes_remaining_allocation,
  position('vv.supply_limit' in pg_get_functiondef(p.oid))>0 as checks_version_supply
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='partner_issuable_voucher_catalog';

-- D. Runtime E2E expectations after test identities/data are seeded:
-- 1) Partner A sees only Versions it is authorized and allocated to issue.
-- 2) Partner B cannot see Partner A-only Versions/allocations.
-- 3) Suspended Partner receives no usable catalog (function rejects inactive account).
-- 4) Partner Staff with staff_access_enabled=false is rejected.
-- 5) Exhausted Allocation disappears from catalog.
-- 6) Exhausted Version supply disappears from catalog.
-- 7) Inactive/archived Version or Template disappears from catalog.
-- 8) Fixed campaign outside its date window disappears from catalog.
