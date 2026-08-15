-- Voucher allocation / FEFO / all-branches freeze runtime E2E
-- Proves admin_engine_allocate_v2 itself (including arbitrary positive days and <=0 rejection),
-- deterministic earliest-expiry-first batch consumption, and immutable all-branches materialisation.
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
  1,50,true,'active',now(),'77777777-7777-4777-8777-777777777777'
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);

do $$
declare
  r100 jsonb;
  r90 jsonb;
  bad_failed boolean:=false;
  id100 uuid;
  id90 uuid;
begin
  r100:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',
    1,'allocation',100,null
  );
  if coalesce((r100->>'success')::boolean,false) is not true then
    raise exception 'Allocation E2E: 100-day RPC failed: %',r100;
  end if;
  if (r100->>'allocation_valid_days')::integer<>100 or r100->>'validity_anchor'<>'allocation' then
    raise exception 'Allocation E2E: 100-day RPC result mismatch: %',r100;
  end if;
  id100:=(r100->>'allocation_id')::uuid;

  perform pg_sleep(0.02);
  r90:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',
    1,'allocation',90,null
  );
  if coalesce((r90->>'success')::boolean,false) is not true then
    raise exception 'Allocation E2E: 90-day RPC failed: %',r90;
  end if;
  if (r90->>'allocation_valid_days')::integer<>90 or r90->>'validity_anchor'<>'allocation' then
    raise exception 'Allocation E2E: 90-day RPC result mismatch: %',r90;
  end if;
  id90:=(r90->>'allocation_id')::uuid;
  if id90=id100 then raise exception 'Allocation E2E: allocation-anchored top-up incorrectly reused prior lot'; end if;

  begin
    perform public.admin_engine_allocate_v2(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'dddddddd-2222-4222-8222-dddddddddddd',
      1,'allocation',0,null
    );
  exception when others then
    if position('at least 1' in sqlerrm)>0 then bad_failed:=true; else raise; end if;
  end;
  if not bad_failed then raise exception 'Allocation E2E: zero allocation days were not rejected'; end if;

  perform set_config('fefo.id100',id100::text,true);
  perform set_config('fefo.id90',id90::text,true);
end;
$$;

-- Partner issuance must consume the 90-day lot first even though it was created later.
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  r1 jsonb;
  r2 jsonb;
  a1 uuid;
  a2 uuid;
  v1 uuid;
  branch_before integer;
begin
  r1:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer 1','0120000101');
  if coalesce((r1->>'success')::boolean,false) is not true then raise exception 'FEFO E2E: first issuance failed: %',r1; end if;
  v1:=(r1->>'voucher_id')::uuid;
  select allocation_id into a1 from public.vouchers where id=v1;
  if a1<>current_setting('fefo.id90')::uuid then
    raise exception 'FEFO E2E: earliest-expiry lot was not consumed first. expected %, got %',current_setting('fefo.id90'),a1;
  end if;

  select count(*) into branch_before from public.voucher_branches where voucher_id=v1;
  if branch_before<1 then raise exception 'FEFO E2E: all-branches voucher materialised no branches'; end if;
  perform set_config('fefo.voucher1',v1::text,true);
  perform set_config('fefo.branch_count_before',branch_before::text,true);

  r2:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer 2','0120000102');
  if coalesce((r2->>'success')::boolean,false) is not true then raise exception 'FEFO E2E: second issuance failed: %',r2; end if;
  select allocation_id into a2 from public.vouchers where id=(r2->>'voucher_id')::uuid;
  if a2<>current_setting('fefo.id100')::uuid then
    raise exception 'FEFO E2E: second issuance did not fall through to 100-day lot. expected %, got %',current_setting('fefo.id100'),a2;
  end if;
end;
$$;

-- Add a new active branch after issuance. The already-issued all-branches voucher must not expand.
reset role;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);
insert into public.branches(id,branch_code,branch_name,address,phone,status)
values('dddddddd-9999-4999-8999-dddddddddddd','FUTURE-FEFO','Future FEFO Branch','Future test address','000-0000000','active');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  v1 uuid:=current_setting('fefo.voucher1')::uuid;
  before_count integer:=current_setting('fefo.branch_count_before')::integer;
  after_count integer;
  future_count integer;
  p jsonb;
  token uuid;
begin
  select count(*) into after_count from public.voucher_branches where voucher_id=v1;
  if after_count<>before_count then
    raise exception 'Branch freeze E2E: old voucher branch count changed from % to % after adding future branch',before_count,after_count;
  end if;
  select count(*) into future_count
  from public.voucher_branches vb
  where vb.voucher_id=v1 and vb.branch_id='dddddddd-9999-4999-8999-dddddddddddd';
  if future_count<>0 then raise exception 'Branch freeze E2E: newly-added branch leaked into issued voucher snapshot'; end if;

  select public_token into token from public.vouchers where id=v1;
  p:=public.get_public_voucher(token);
  if exists(
    select 1 from jsonb_array_elements(coalesce(p->'branches','[]'::jsonb)) j
    where j->>'branch_code'='FUTURE-FEFO'
  ) then
    raise exception 'Branch freeze E2E: public RPC dynamically broadened old voucher after new branch';
  end if;
end;
$$;

reset role;
rollback;
