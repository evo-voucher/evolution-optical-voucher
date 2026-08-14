-- Partner password-reset audit contract for migration 040.

DO $$
DECLARE src text;
BEGIN
  if to_regprocedure('public.admin_record_partner_password_reset(uuid)') is null then
    raise exception 'admin_record_partner_password_reset(uuid) is missing';
  end if;

  select pg_get_functiondef('public.admin_record_partner_password_reset(uuid)'::regprocedure) into src;
  if src not ilike '%security definer%' or src not ilike '%is_voucher_admin%' then
    raise exception 'Password reset audit RPC must be SECURITY DEFINER and Admin-only';
  end if;
  if src not ilike '%insert into public.admin_audit_log%' then
    raise exception 'Password reset audit RPC must own the audit write';
  end if;

  if has_function_privilege('anon','public.admin_record_partner_password_reset(uuid)','EXECUTE') then
    raise exception 'anon must not execute Partner password-reset audit RPC';
  end if;
  if not has_function_privilege('authenticated','public.admin_record_partner_password_reset(uuid)','EXECUTE') then
    raise exception 'authenticated role must reach RPC; function performs Admin authorization';
  end if;
END;
$$;

select
  has_function_privilege('anon','public.admin_record_partner_password_reset(uuid)','EXECUTE') anon_execute,
  has_function_privilege('authenticated','public.admin_record_partner_password_reset(uuid)','EXECUTE') authenticated_execute;
