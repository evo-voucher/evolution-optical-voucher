-- Voucher delivery policy snapshot contract

DO $$
DECLARE
  missing text;
BEGIN
  select string_agg(x.col,', ' order by x.col) into missing
  from (values
    ('validity_anchor_snapshot'),('validity_value_snapshot'),('validity_unit_snapshot'),
    ('theme_code_snapshot'),('theme_config_snapshot'),('greeting_snapshot'),('terms_snapshot')
  ) x(col)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name='vouchers' and c.column_name=x.col
  );
  if missing is not null then raise exception 'Voucher snapshot columns missing: %',missing; end if;
END $$;

DO $$
BEGIN
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='voucher_versions' and column_name='greeting_text') then
    raise exception 'voucher_versions.greeting_text missing';
  end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='partner_voucher_allocations' and column_name='validity_anchor') then
    raise exception 'partner_voucher_allocations.validity_anchor missing';
  end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='partner_voucher_allocations' and column_name='allocation_valid_days') then
    raise exception 'partner_voucher_allocations.allocation_valid_days missing';
  end if;
END $$;

DO $$
DECLARE src text;
BEGIN
  select lower(pg_get_functiondef('public.snapshot_voucher_delivery_policy()'::regprocedure)) into src;
  if position('theme_code_snapshot' in src)=0 then raise exception 'Theme is not snapshotted'; end if;
  if position('greeting_snapshot' in src)=0 then raise exception 'Greeting is not snapshotted'; end if;
  if position('allocation_valid_days' in src)=0 then raise exception 'Allocation-anchored validity is not supported at snapshot boundary'; end if;
  if position('little gift for you' in src)=0 then raise exception 'Default WhatsApp greeting contract missing'; end if;
END $$;

DO $$
DECLARE src text;
BEGIN
  select lower(pg_get_functiondef('public.guard_voucher_delivery_snapshot_immutable()'::regprocedure)) into src;
  if position('immutable' in src)=0 then raise exception 'Issued Voucher snapshot immutability guard missing'; end if;
END $$;

DO $$
DECLARE src text;
BEGIN
  select lower(pg_get_functiondef('public.get_public_voucher(uuid)'::regprocedure)) into src;
  if position('theme_config_snapshot' in src)=0 then raise exception 'Public Voucher must read frozen theme snapshot'; end if;
  if position('greeting_snapshot' in src)=0 then raise exception 'Public Voucher must read frozen greeting snapshot'; end if;
  if position('validity_anchor_snapshot' in src)=0 then raise exception 'Public Voucher must expose frozen validity basis'; end if;
END $$;

select
  has_function_privilege('anon','public.get_public_voucher(uuid)','EXECUTE') as anon_public_voucher,
  has_function_privilege('authenticated','public.get_public_voucher(uuid)','EXECUTE') as authenticated_public_voucher;
