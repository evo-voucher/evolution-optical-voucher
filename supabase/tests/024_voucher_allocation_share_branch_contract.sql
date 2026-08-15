-- Voucher allocation validity + frozen branch/share execution contract.

DO $$
BEGIN
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted') then
    raise exception 'vouchers.branch_scope_snapshotted missing';
  end if;
  if to_regprocedure('public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid)') is null then
    raise exception 'admin_engine_allocate_v2 missing';
  end if;
  if to_regprocedure('public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text)') is null then
    raise exception 'admin_publish_voucher_version_v2 missing';
  end if;
  if to_regprocedure('public.get_partner_voucher_share(uuid)') is null then
    raise exception 'get_partner_voucher_share missing';
  end if;
END $$;

DO $$
DECLARE
  src text;
BEGIN
  select lower(pg_get_functiondef('public.snapshot_voucher_delivery_policy()'::regprocedure)) into src;
  if position('a little gift for you 🎁✨' in src)=0 then raise exception 'approved default greeting missing'; end if;
  if position('v_default_greeting' in src)=0 or position('v_occasion' in src)=0 then
    raise exception 'occasion greeting must extend, not replace, the approved default greeting';
  end if;

  select lower(pg_get_functiondef('public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid)'::regprocedure)) into src;
  if position('allocation_valid_days' in src)=0 then raise exception 'allocation day validity missing'; end if;
  if position('make_interval(days=>p_allocation_valid_days)' in replace(src,' ',''))=0 then
    raise exception 'allocation expiry must derive from Admin allocation time';
  end if;
  if position('v_anchor=''allocation''' in replace(src,' ',''))=0 then raise exception 'allocation anchor branch missing'; end if;

  select lower(pg_get_functiondef('public.issue_engine_voucher(uuid,text,text)'::regprocedure)) into src;
  if position('auth.uid()' in src)=0 or position('p_partner_id' in src)>0 then
    raise exception 'issuance tenant must remain Auth-derived';
  end if;
  if position('branch_scope_snapshotted=true' in replace(src,' ',''))=0 then
    raise exception 'issue path must seal branch snapshot';
  end if;
  if position('validity_anchor' in src)=0 or position('valid_until' in src)=0 then
    raise exception 'issue path must honor allocation validity';
  end if;
  if position('insert into public.voucher_branches' in src)=0 then
    raise exception 'issue path must materialise branch membership';
  end if;

  select lower(pg_get_functiondef('public.redeem_voucher(text,text,text,text)'::regprocedure)) into src;
  if position('branch_scope_snapshotted' in src)=0 or position('voucher_branches' in src)=0 then
    raise exception 'redemption must honor frozen branch membership';
  end if;

  select lower(pg_get_functiondef('public.get_partner_voucher_share(uuid)'::regprocedure)) into src;
  if position('current_partner_id()' in src)=0 then raise exception 'Partner share must be tenant scoped'; end if;
  if position('message_body' in src)=0 or position('redeem at:' in src)=0 then
    raise exception 'WhatsApp share body or branch block missing';
  end if;
  if position('address' in src)=0 or position('phone' in src)=0 then
    raise exception 'WhatsApp share must include branch address and phone';
  end if;
END $$;

DO $$
BEGIN
  if has_function_privilege('anon','public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid)','EXECUTE') then
    raise exception 'anon must not allocate Voucher stock';
  end if;
  if has_function_privilege('anon','public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text)','EXECUTE') then
    raise exception 'anon must not publish Voucher Versions';
  end if;
  if has_function_privilege('anon','public.get_partner_voucher_share(uuid)','EXECUTE') then
    raise exception 'anon must not access Partner share payload';
  end if;
  if not has_function_privilege('authenticated','public.get_partner_voucher_share(uuid)','EXECUTE') then
    raise exception 'authenticated Partner realm requires share execution';
  end if;
END $$;
