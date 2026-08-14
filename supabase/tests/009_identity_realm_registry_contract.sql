-- Non-destructive operational identity realm registry checks.
-- Run only after migrations on the verified NEW Supabase target.

select to_regclass('public.operational_identity_realms') as operational_identity_realms,
       to_regprocedure('public.claim_operational_identity_realm(uuid,text)') as claim_realm,
       to_regprocedure('public.release_operational_identity_realm(uuid,text)') as release_realm;

-- Registry must have one primary-key uniqueness boundary on user_id.
select c.conname,c.contype,pg_get_constraintdef(c.oid) as definition
from pg_constraint c
where c.conrelid='public.operational_identity_realms'::regclass
  and c.contype='p';

-- Internal claim/release helpers must not be browser executable, but trusted
-- service-role identity provisioning must be able to maintain the registry.
select p.proname,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig,','),'') as proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('claim_operational_identity_realm','release_operational_identity_realm')
order by p.proname;

-- Expected: SECURITY DEFINER=true, search_path=public,
-- anon=false, authenticated=false, service_role=true.

-- The obsolete full UNIQUE(user_id) constraint on partner_users must be gone.
select c.conname,pg_get_constraintdef(c.oid) as unexpected_full_unique
from pg_constraint c
where c.conrelid='public.partner_users'::regclass
  and c.contype='u'
  and cardinality(c.conkey)=1
  and exists (
    select 1 from pg_attribute a
    where a.attrelid=c.conrelid and a.attnum=c.conkey[1] and a.attname='user_id'
  );
-- Expected: zero rows.

-- 018's one-live-membership partial unique index must remain.
select indexname,indexdef
from pg_indexes
where schemaname='public'
  and tablename='partner_users'
  and indexname='uq_partner_users_live_user';
-- Expected: exactly one row and predicate "removed_at IS NULL".

-- Realm guard triggers must still exist on all three identity tables.
select tgname,tgrelid::regclass as table_name
from pg_trigger
where not tgisinternal
  and tgname in (
    'admin_users_guard_identity_realm',
    'partner_users_guard_identity_realm',
    'staff_users_guard_identity_realm'
  )
order by tgname;
-- Expected: exactly three rows.

-- Required runtime concurrency test with real disposable Auth identities:
-- A) concurrently activate the same UID as Admin and Staff -> exactly one transaction succeeds;
-- B) concurrently activate the same UID as Partner and Staff -> exactly one succeeds;
-- C) remove/deactivate the winning realm, then activate a different realm -> succeeds;
-- D) remove a historical Partner membership, then create a later Partner membership for the same UID -> succeeds while only one removed_at IS NULL row exists.
