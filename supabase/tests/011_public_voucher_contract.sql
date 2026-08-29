-- Non-destructive public Voucher contract checks.
-- Run only after migrations on the verified NEW Supabase target.

select to_regprocedure('public.get_public_voucher(uuid)') as get_public_voucher;
-- Expected: non-null.

select p.proname,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig,','),'') as proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='get_public_voucher';
-- Expected: SECURITY DEFINER=true, search_path=public, anon_execute=true.

-- Public function source must not expose sensitive internal fields.
with f as (
  select lower(pg_get_functiondef(p.oid)) as def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.oid='public.get_public_voucher(uuid)'::regprocedure
)
select forbidden_field
from f,
lateral (values
  ('customer_phone'),
  ('issued_by_user_id'),
  ('revoked_by_user_id'),
  ('allocation_id'),
  ('metadata')
) x(forbidden_field)
where position(forbidden_field in f.def)>0;
-- Expected: zero rows.

-- Runtime checks with a disposable issued Voucher are still required:
-- A) anon + valid public_token returns success=true and only customer-facing data;
-- B) missing/random token returns success=false without row existence detail leakage;
-- C) expiry/status is server-derived and cannot be overridden from the browser;
-- D) branch list contains only active branches allowed for that Voucher;
-- E) public lookup never mutates Voucher or Redemption state.
-- F) customer_name is masked (for example, "Current Customer" becomes "C***").
