-- Partner Staff server-management contract for migration 039.

DO $$
DECLARE missing text;
BEGIN
  with required(sig) as (
    values
      ('partner_provision_staff(uuid,text,text,uuid)'::text),
      ('partner_update_staff_profile(uuid,text,text,uuid)'::text),
      ('partner_record_staff_password_reset(uuid,uuid)'::text)
  )
  select string_agg(sig,', ') into missing
  from required
  where to_regprocedure('public.'||sig) is null;
  if missing is not null then raise exception 'Missing Partner Staff server RPC(s): %',missing; end if;
END;
$$;

DO $$
DECLARE r record;
BEGIN
  for r in
    select p.oid,p.proname,p.prosecdef,p.proconfig,pg_get_functiondef(p.oid) src
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'partner_provision_staff','partner_update_staff_profile','partner_record_staff_password_reset'
    )
  loop
    if not r.prosecdef then raise exception '% must be SECURITY DEFINER',r.proname; end if;
    if not ('search_path=public'=any(coalesce(r.proconfig,array[]::text[]))) then
      raise exception '% must pin search_path=public',r.proname;
    end if;
    if has_function_privilege('anon',r.oid,'EXECUTE') or has_function_privilege('authenticated',r.oid,'EXECUTE') then
      raise exception '% must not be browser-callable',r.proname;
    end if;
    if not has_function_privilege('service_role',r.oid,'EXECUTE') then
      raise exception 'service_role must execute %',r.proname;
    end if;
    if r.src not ilike '%is_trusted_service_role%' or r.src not ilike '%role=''partner_admin''%' then
      raise exception '% must revalidate trusted server and Partner Admin actor',r.proname;
    end if;
  end loop;
END;
$$;

DO $$
DECLARE src text;
BEGIN
  select pg_get_functiondef('public.partner_provision_staff(uuid,text,text,uuid)'::regprocedure) into src;
  if src not ilike '%for update%' or src not ilike '%staff_limit%' then
    raise exception 'Partner Staff provisioning must serialize and enforce staff_limit';
  end if;
  if src ilike '%p_partner_id%' then
    raise exception 'Partner Staff provisioning must derive Partner from actor, not accept Partner id';
  end if;
END;
$$;

select
  has_function_privilege('service_role','public.partner_provision_staff(uuid,text,text,uuid)','EXECUTE') service_create,
  has_function_privilege('authenticated','public.partner_provision_staff(uuid,text,text,uuid)','EXECUTE') browser_create,
  has_function_privilege('service_role','public.partner_update_staff_profile(uuid,text,text,uuid)','EXECUTE') service_update,
  has_function_privilege('authenticated','public.partner_update_staff_profile(uuid,text,text,uuid)','EXECUTE') browser_update;
