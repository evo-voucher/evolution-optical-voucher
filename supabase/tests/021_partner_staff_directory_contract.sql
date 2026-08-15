-- Partner Staff directory contract

DO $$
BEGIN
  IF to_regprocedure('public.partner_staff_directory()') IS NULL THEN
    RAISE EXCEPTION 'partner_staff_directory() missing';
  END IF;
END $$;

DO $$
DECLARE
  v_src text;
BEGIN
  select lower(pg_get_functiondef('public.partner_staff_directory()'::regprocedure)) into v_src;
  if position('auth.uid()' in v_src)=0 then
    raise exception 'partner_staff_directory must derive caller identity from auth.uid()';
  end if;
  if position('partner_admin' in v_src)=0 then
    raise exception 'partner_staff_directory must require Partner Admin';
  end if;
  if position('p_partner_id' in v_src)>0 then
    raise exception 'partner_staff_directory must not accept or depend on caller-supplied partner_id';
  end if;
END $$;

select
  has_function_privilege('anon','public.partner_staff_directory()','EXECUTE') as anon_execute,
  has_function_privilege('authenticated','public.partner_staff_directory()','EXECUTE') as authenticated_execute;

DO $$
BEGIN
  IF has_function_privilege('anon','public.partner_staff_directory()','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute partner_staff_directory';
  END IF;
  IF NOT has_function_privilege('authenticated','public.partner_staff_directory()','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated must execute partner_staff_directory';
  END IF;
END $$;
