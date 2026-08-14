-- Atomic identity provisioning contract.
-- Non-destructive structural assertions for migration 038.

DO $$
DECLARE
  missing text;
BEGIN
  with required(sig) as (
    values
      ('admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid)'::text),
      ('admin_provision_staff(uuid,text,uuid,text,text,uuid)'::text)
  )
  select string_agg(r.sig,', ') into missing
  from required r
  where to_regprocedure('public.'||r.sig) is null;

  if missing is not null then
    raise exception 'Missing identity provisioning RPC(s): %',missing;
  end if;
END;
$$;

DO $$
DECLARE r record;
BEGIN
  for r in
    select p.oid,p.proname,p.prosecdef,p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('admin_provision_partner','admin_provision_staff')
  loop
    if not r.prosecdef then
      raise exception '% must be SECURITY DEFINER',r.proname;
    end if;
    if not ('search_path=public'=any(coalesce(r.proconfig,array[]::text[]))) then
      raise exception '% must pin search_path=public',r.proname;
    end if;
    if has_function_privilege('anon',r.oid,'EXECUTE') then
      raise exception 'anon must not execute %',r.proname;
    end if;
    if has_function_privilege('authenticated',r.oid,'EXECUTE') then
      raise exception 'authenticated must not execute % directly',r.proname;
    end if;
    if not has_function_privilege('service_role',r.oid,'EXECUTE') then
      raise exception 'service_role must execute %',r.proname;
    end if;
  end loop;
END;
$$;

DO $$
DECLARE src text;
BEGIN
  select pg_get_functiondef('public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid)'::regprocedure) into src;
  if src not ilike '%is_trusted_service_role%' then
    raise exception 'Partner provisioning must require trusted service role';
  end if;
  if src not ilike '%admin_users%' or src not ilike '%status=''active''%' then
    raise exception 'Partner provisioning must validate active Admin actor';
  end if;
  if src not ilike '%insert into public.partners%' or src not ilike '%insert into public.partner_users%'
     or src not ilike '%insert into public.partner_claim_settings%' or src not ilike '%insert into public.admin_audit_log%' then
    raise exception 'Partner provisioning must atomically own all required business rows';
  end if;
END;
$$;

DO $$
DECLARE src text;
BEGIN
  select pg_get_functiondef('public.admin_provision_staff(uuid,text,uuid,text,text,uuid)'::regprocedure) into src;
  if src not ilike '%is_trusted_service_role%' then
    raise exception 'Staff provisioning must require trusted service role';
  end if;
  if src not ilike '%admin_users%' or src not ilike '%insert into public.staff_users%'
     or src not ilike '%insert into public.admin_audit_log%' then
    raise exception 'Staff provisioning contract incomplete';
  end if;
END;
$$;

select
  has_function_privilege('service_role','public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid)','EXECUTE') as partner_service_execute,
  has_function_privilege('authenticated','public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid)','EXECUTE') as partner_browser_execute,
  has_function_privilege('service_role','public.admin_provision_staff(uuid,text,uuid,text,text,uuid)','EXECUTE') as staff_service_execute,
  has_function_privilege('authenticated','public.admin_provision_staff(uuid,text,uuid,text,text,uuid)','EXECUTE') as staff_browser_execute;
