-- Partner / Partner Staff business-role boundary contract.
-- Business rule: Admin owns Voucher definition/allocation. Partner and Partner Staff may issue only authorised Vouchers.
-- Partner Admin alone may manage Partner Staff. Partner Staff is read/issue only within its Partner tenant.

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'voucher_templates','voucher_versions','voucher_version_branches','voucher_rules',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events'
  ] LOOP
    IF has_table_privilege('authenticated', format('public.%I',t), 'INSERT')
       OR has_table_privilege('authenticated', format('public.%I',t), 'UPDATE')
       OR has_table_privilege('authenticated', format('public.%I',t), 'DELETE') THEN
      RAISE EXCEPTION 'authenticated must not directly mutate %', t;
    END IF;
  END LOOP;
END $$;

DO $$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.issue_engine_voucher(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'issue_engine_voucher missing';
  END IF;

  SELECT lower(pg_get_functiondef('public.issue_engine_voucher(uuid,text,text)'::regprocedure)) INTO v_src;

  IF position('auth.uid()' in v_src)=0 THEN
    RAISE EXCEPTION 'issue_engine_voucher must derive caller identity from auth.uid()';
  END IF;
  IF position('partner_admin' in v_src)=0 OR position('partner_staff' in v_src)=0 THEN
    RAISE EXCEPTION 'issue_engine_voucher must explicitly support Partner Admin and Partner Staff issuance roles';
  END IF;
  IF position('partner_voucher_access' in v_src)=0 OR position('partner_voucher_allocations' in v_src)=0 THEN
    RAISE EXCEPTION 'issue_engine_voucher must enforce Admin-controlled Partner access/allocation';
  END IF;
  IF position('p_partner_id' in v_src)>0 THEN
    RAISE EXCEPTION 'issue_engine_voucher must not trust caller-supplied partner_id';
  END IF;
END $$;

DO $$
BEGIN
  IF has_function_privilege('anon','public.issue_engine_voucher(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute issue_engine_voucher';
  END IF;
  IF NOT has_function_privilege('authenticated','public.issue_engine_voucher(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated Partner identities must be able to execute issue_engine_voucher';
  END IF;
END $$;

DO $$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.partner_staff_directory()') IS NULL THEN
    RAISE EXCEPTION 'partner_staff_directory missing';
  END IF;
  SELECT lower(pg_get_functiondef('public.partner_staff_directory()'::regprocedure)) INTO v_src;
  IF position('partner_admin' in v_src)=0 THEN
    RAISE EXCEPTION 'Partner Staff directory must remain Partner Admin only';
  END IF;
END $$;

-- Partner Staff may read its own tenant Voucher data via current_partner_id(), but cannot read the tenant Staff directory through partner_users RLS.
DO $$
DECLARE
  v_policy text;
BEGIN
  SELECT lower(pg_get_expr(polqual,polrelid))
  INTO v_policy
  FROM pg_policy p
  JOIN pg_class c ON c.oid=p.polrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='partner_users' AND p.polname='partner_users_read_scope';

  IF v_policy IS NULL OR position('partner_admin' in v_policy)=0 THEN
    RAISE EXCEPTION 'partner_users read scope must restrict same-tenant Staff directory visibility to Partner Admin';
  END IF;
END $$;
