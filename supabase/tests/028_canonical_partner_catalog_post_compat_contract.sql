-- Canonical Partner catalog must survive later hosted/admin compatibility migrations.

DO $$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.partner_issuable_voucher_catalog()') IS NULL THEN
    RAISE EXCEPTION 'partner_issuable_voucher_catalog() missing';
  END IF;

  SELECT lower(pg_get_functiondef('public.partner_issuable_voucher_catalog()'::regprocedure))
  INTO v_src;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='voucher_versions' AND column_name='validity_mode'
  ) THEN
    IF position('vv.validity_mode' in v_src)=0 THEN
      RAISE EXCEPTION 'canonical Partner catalog must use voucher_versions.validity_mode';
    END IF;
    IF position('vv.validity_type' in v_src)>0 THEN
      RAISE EXCEPTION 'canonical Partner catalog must not reference legacy voucher_versions.validity_type';
    END IF;
  END IF;

  IF position('partner_admin' in v_src)=0 OR position('partner_staff' in v_src)=0 THEN
    RAISE EXCEPTION 'Partner catalog must preserve Partner Admin and Partner Staff access';
  END IF;
  IF position('admin' in v_src)=0 THEN
    RAISE EXCEPTION 'Partner catalog must preserve Admin superuser Partner-portal compatibility';
  END IF;
END $$;

DO $$
BEGIN
  IF has_function_privilege('anon','public.partner_issuable_voucher_catalog()','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute partner_issuable_voucher_catalog';
  END IF;
  IF NOT has_function_privilege('authenticated','public.partner_issuable_voucher_catalog()','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated must execute partner_issuable_voucher_catalog';
  END IF;
END $$;
