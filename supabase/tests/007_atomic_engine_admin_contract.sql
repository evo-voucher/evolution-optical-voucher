-- Non-destructive atomic Voucher Engine Admin contract checks.
-- Run only after migrations on the verified NEW Supabase target.

with required_functions(signature) as (
  values
    ('admin_engine_allocate(uuid,uuid,integer,uuid)'),
    ('admin_engine_revoke_unissued(uuid,integer,text,uuid)'),
    ('admin_engine_retire_version(uuid,text,uuid)')
)
select r.signature as missing_function
from required_functions r
where to_regprocedure('public.' || r.signature) is null;

-- Expected: zero rows.

select p.proname,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig, ','),'') as proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'admin_engine_allocate',
    'admin_engine_revoke_unissued',
    'admin_engine_retire_version'
  )
order by p.proname;

-- Review expectations:
-- 1) SECURITY DEFINER=true and search_path=public.
-- 2) anon_execute=false.
-- 3) authenticated_execute=true, but function itself requires active Admin identity.
-- 4) service_role_execute=true, but a service-role call must provide an active Admin actor_user_id.

-- Source-level concurrency contract checks.
select p.proname,
       position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))>0 as uses_advisory_lock,
       position('for update' in lower(pg_get_functiondef(p.oid)))>0 as uses_row_lock
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('admin_engine_allocate','admin_engine_revoke_unissued','admin_engine_retire_version')
order by p.proname;

-- Behavioral runtime checks with real Admin Auth context are still required:
-- A) concurrent allocation increments for same Partner+Version must both be preserved;
-- B) revoke racing with issuance must never revoke already-issued capacity;
-- C) retire racing with issuance must not permit issuance after Version becomes inactive;
-- D) non-Admin authenticated caller must be rejected;
-- E) service_role call without a valid active Admin actor_user_id must be rejected.
