-- Voucher allocation FEFO + future-branch freeze runtime E2E
-- Proves admin_engine_allocate_v2 itself accepts arbitrary positive allocation days,
-- rejects non-positive allocation days, creates independent allocation lots,
-- issue_engine_voucher consumes allocation-anchored lots earliest-expiry-first,
-- and an all-branches issued Voucher cannot gain branches created later.
-- Disposable local CI only; all fixtures roll back.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('77777777-7777-4777-8777-777777777777','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fefo-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('88888888-8888-4888-8888-888888888888','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fefo-partner@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values('77777777-7777-4777-8777-777777777777','FEFO Admin','active');

insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','FEFO-P','FEFO Partner',0,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values('88888888-8888-4888-8888-888888888888','dddddddd-dddd-4ddd-8ddd-dddddddddddd','partner_admin','active','FEFO Partner Admin','fefo-partner@example.invalid');

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',true,'77777777-7777-4777-8777-777777777777');

insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,theme_config,created_by)
values('dddddddd-1111-4111-8111-dddddddddddd','FEFO','FEFO Voucher','promotion','active','default','{}'::jsonb,'77777777-7777-4777-8777-777777777777');

insert into public.voucher_versions(
  id,template_id,version_no,version_name,face_value,validity_mode,valid_days,
  usage_limit,supply_limit,all_branches,status,effective_from,created_by
) values(
  'dddddddd-2222-4222-8222-dddddddddddd','dddddddd-1111-4111-8111-dddddddddddd',1,'FEFO v1',60,'days',30,
  1,20,true,'active',now(),'77777777-7777-4777-8777-777777777777'
);

-- Exercise the real Admin RPC as an authenticated active Admin.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);

do $$
declare
  r100 jsonb;
  r90 jsonb;
  rejected boolean:=false;
  id100 uuid;
  id90 uuid;
  days100 integer;
  days90 integer;
  until100 timestamptz;
  until90 timestamptz;
begin
  r100:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',
    1,'allocation',100,null
  );
  r90:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',
    1,'allocation',90,null
  );

  if coalesce((r100->>'success')::boolean,false) is not true or coalesce((r90->>'success')::boolean,false) is not true then
    raise exception 'FEFO E2E: allocation RPC did not succeed: 100=%, 90=%',r100,r90;
  end if;

  id100:=(r100->>'allocation_id')::uuid;
  id90:=(r90->>'allocation_id')::uuid;
  if id100=id90 then raise exception 'FEFO E2E: allocation-anchored top-ups must create independent lots'; end if;

  select allocation_valid_days,valid_until into days100,until100 from public.partner_voucher_allocations where id=id100;
  select allocation_valid_days,valid_until into days90,until90 from public.partner_voucher_allocations where id=id90;
  if days100<>100 or days90<>90 then raise exception 'FEFO E2E: arbitrary allocation days not persisted: %, %',days100,days90; end if;
  if until90>=until100 then raise exception 'FEFO E2E: 90-day lot must expire before 100-day lot'; end if;

  begin
    perform public.admin_engine_allocate_v2(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'dddddddd-2222-4222-8222-dddddddddddd',
      1,'allocation',0,null
    );
  exception when others then
    if position('Allocation validity days must be at least 1' in sqlerrm)>0 then rejected:=true; else raise; end if;
  end;
  if not rejected then raise exception 'FEFO E2E: allocation_valid_days=0 was not rejected'; end if;

  perform set_config('fefo.alloc100',id100::text,true);
  perform set_config('fefo.alloc90',id90::text,true);
end;
$$;

-- Partner issuance must consume the 90-day lot before the older-created 100-day lot.
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  first_issue jsonb;
  second_issue jsonb;
  first_id uuid;
  second_id uuid;
  first_alloc uuid;
  second_alloc uuid;
  first_token uuid;
  snap_count integer;
begin
  first_issue:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer 1','0121000001');
  if coalesce((first_issue->>'success')::boolean,false) is not true then raise exception 'FEFO E2E: first issue failed: %',first_issue; end if;
  first_id:=(first_issue->>'voucher_id')::uuid;
  first_token:=(first_issue->>'public_token')::uuid;
  select allocation_id into first_alloc from public.vouchers where id=first_id;
  if first_alloc<>current_setting('fefo.alloc90')::uuid then
    raise exception 'FEFO E2E: first issue did not consume earliest-expiry 90-day lot: got %, expected %',first_alloc,current_setting('fefo.alloc90');
  end if;

  select count(*) into snap_count from public.voucher_branches where voucher_id=first_id;
  if snap_count<1 then raise exception 'FEFO E2E: all-branches issue did not materialise branch snapshot'; end if;

  second_issue:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer 2','0121000002');
  if coalesce((second_issue->>'success')::boolean,false) is not true then raise exception 'FEFO E2E: second issue failed: %',second_issue; end if;
  second_id:=(second_issue->>'voucher_id')::uuid;
  select allocation_id into second_alloc from public.vouchers where id=second_id;
  if second_alloc<>current_setting('fefo.alloc100')::uuid then
    raise exception 'FEFO E2E: second issue did not fall through to remaining 100-day lot: got %, expected %',second_alloc,current_setting('fefo.alloc100');
  end if;

  perform set_config('fefo.first_voucher',first_id::text,true);
  perform set_config('fefo.first_token',first_token::text,true);
  perform set_config('fefo.first_branch_count',snap_count::text,true);
end;
$$;

-- Add a brand-new active branch after the Voucher was issued.
reset role;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);
insert into public.branches(id,branch_code,branch_name,address,phone,status)
values('dddddddd-9999-4999-8999-dddddddddddd','FUTURE','Future Branch','Future Address','03-00000000','active');

-- Existing all-branches Voucher must not gain the future branch in storage or public output.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  current_count integer;
  future_count integer;
  p jsonb;
  branches jsonb;
begin
  select count(*) into current_count from public.voucher_branches where voucher_id=current_setting('fefo.first_voucher')::uuid;
  if current_count<>current_setting('fefo.first_branch_count')::integer then
    raise exception 'FEFO E2E: issued branch snapshot count changed after future branch creation: before %, after %',current_setting('fefo.first_branch_count'),current_count;
  end if;
  select count(*) into future_count
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=current_setting('fefo.first_voucher')::uuid and b.branch_code='FUTURE';
  if future_count<>0 then raise exception 'FEFO E2E: future branch leaked into immutable voucher_branches snapshot'; end if;

  p:=public.get_public_voucher(current_setting('fefo.first_token')::uuid);
  if coalesce((p->>'success')::boolean,false) is not true then raise exception 'FEFO E2E: public Voucher lookup failed: %',p; end if;
  branches:=coalesce(p->'branches','[]'::jsonb);
  if exists(select 1 from jsonb_array_elements(branches) e where e->>'branch_code'='FUTURE') then
    raise exception 'FEFO E2E: future branch leaked into public frozen branch list: %',branches;
  end if;
end;
$$;

reset role;
rollback;
