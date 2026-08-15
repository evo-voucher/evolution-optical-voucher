-- Voucher validity-anchor + frozen presentation/share contract.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='voucher_versions' AND column_name='validity_anchor'
  ) THEN RAISE EXCEPTION 'voucher_versions.validity_anchor missing'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='voucher_versions' AND column_name='occasion_greeting'
  ) THEN RAISE EXCEPTION 'voucher_versions.occasion_greeting missing'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='vouchers' AND column_name='presentation_snapshot'
  ) THEN RAISE EXCEPTION 'vouchers.presentation_snapshot missing'; END IF;
END $$;

DO $$
DECLARE
  v_issue text;
  v_redeem text;
  v_public text;
  v_share text;
  v_publish text;
  v_allocate text;
BEGIN
  select lower(pg_get_functiondef('public.issue_engine_voucher(uuid,text,text)'::regprocedure)) into v_issue;
  if position('validity_anchor' in v_issue)=0 then
    raise exception 'issue_engine_voucher must honor validity_anchor';
  end if;
  if position('presentation_snapshot' in v_issue)=0 then
    raise exception 'issue_engine_voucher must freeze presentation_snapshot';
  end if;
  if position('a.valid_until' in v_issue)=0 then
    raise exception 'allocation-anchored issue path must use allocation validity';
  end if;
  if position('insert into public.voucher_branches' in v_issue)=0 then
    raise exception 'issue_engine_voucher must materialize issued branch scope';
  end if;
  if position('a little gift for you 🎁✨' in v_issue)=0 then
    raise exception 'canonical share intro missing from issue snapshot';
  end if;

  select lower(pg_get_functiondef('public.redeem_voucher(text,text,text,text)'::regprocedure)) into v_redeem;
  if position('v_has_branch_snapshot' in v_redeem)=0 then
    raise exception 'redeem_voucher must prefer materialized branch snapshot';
  end if;
  if position('voucher_branches' in v_redeem)=0 then
    raise exception 'redeem_voucher branch snapshot lookup missing';
  end if;

  select lower(pg_get_functiondef('public.get_public_voucher(uuid)'::regprocedure)) into v_public;
  if position('presentation_snapshot' in v_public)=0 then
    raise exception 'public Voucher view must read issued presentation snapshot';
  end if;
  if position('theme_config' in v_public)=0 then
    raise exception 'public Voucher view must expose frozen theme config';
  end if;

  select lower(pg_get_functiondef('public.get_partner_voucher_share(uuid)'::regprocedure)) into v_share;
  if position('current_partner_id()' in v_share)=0 then
    raise exception 'share payload must be Partner-tenant scoped';
  end if;
  if position('message_body' in v_share)=0 or position('redeem at:' in v_share)=0 then
    raise exception 'share payload must include canonical WhatsApp message and branches';
  end if;

  select lower(pg_get_functiondef('public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text)'::regprocedure)) into v_publish;
  if position('for update' in v_publish)=0 or position('max(version_no)' in v_publish)=0 then
    raise exception 'v2 publish must preserve serialized version numbering';
  end if;
  if position('allocation-anchored validity currently supports days only' in v_publish)=0 then
    raise exception 'v2 publish must enforce allocation validity semantics';
  end if;

  select lower(pg_get_functiondef('public.admin_engine_allocate_v2(uuid,uuid,integer,uuid)'::regprocedure)) into v_allocate;
  if position('make_interval(days=>v_days)' in replace(v_allocate,' ',''))=0 then
    raise exception 'allocation v2 must derive batch expiry from Admin allocation time';
  end if;
END $$;

DO $$
BEGIN
  IF has_function_privilege('anon','public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not publish Voucher Versions';
  END IF;
  IF has_function_privilege('anon','public.admin_engine_allocate_v2(uuid,uuid,integer,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not allocate Voucher batches';
  END IF;
  IF has_function_privilege('anon','public.get_partner_voucher_share(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not use Partner share RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.get_partner_voucher_share(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated Partner users need share RPC execution';
  END IF;
END $$;
