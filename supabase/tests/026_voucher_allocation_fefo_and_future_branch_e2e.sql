-- Voucher allocation runtime E2E: authoritative Admin RPC, positive-day validation,
-- FEFO batch consumption, and immutable all-branches issuance snapshots.
-- Disposable local CI only; all fixtures are rolled back.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('77777777-7777-4777-8777-777777777777','00000000-0000-0000-0000-000000000000','authenticated','authenticated','allocation-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('88888888-8888-4888-8888-888888888888','00000000-0000-0000-0000-000000000000','authenticated','authenticated','allocation-partner@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);
set local role authenticated;

reset role;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status)
values('77777777-7777-4777-8777-777777777777','Allocation Admin','active');
insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','ALLOC-P','Allocation Partner',0,5,true,'active');
insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values('88888888-8888-4888-8888-888888888888','dddddddd-dddd-4ddd-8ddd-dddddddddddd','partner_admin','active','Allocation Partner Admin','allocation-partner@example.invalid');
insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',true,'77777777-7777-4777-8777-777777777777');
insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,theme_config,created_by)
values('dddddddd-1111-4111-8111-dddddddddddd','ALLOC-FEFO','Allocation FEFO Voucher','promotion','active','default','{}'::jsonb,'77777777-7777-4777-8777-777777777777');
insert into public.voucher_versions(
  id,template_id,version_no,version_name,face_value,validity_mode,valid_days,
  usage_limit,supply_limit,all_branches,status,effective_from,created_by
) values(
  'dddddddd-2222-4222-8222-dddddddddddd','dddddddd-1111-4111-8111-dddddddddddd',1,'Allocation FEFO v1',60,'days',365,
  1,20,true,'active',now(),'77777777-7777-4777-8777-777777777777'
);
update public.voucher_templates set current_version_id='dddddddd-2222-4222-8222-dddddddddddd' where id='dddddddd-1111-4111-8111-dddddddddddd';

-- Call the real Admin RPC as an authenticated Admin. Two allocation-anchored
-- batches must remain distinct because each owns its own validity clock.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);

do $$
declare
  r90 jsonb;
  r100 jsonb;
  a90 uuid;
  a100 uuid;
  d90 integer;
  d100 integer;
  vf timestamptz;
  vu timestamptz;
begin
  r90:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',1,'allocation',90,null
  );
  r100:=public.admin_engine_allocate_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'dddddddd-2222-4222-8222-dddddddddddd',1,'allocation',100,null
  );
  if coalesce((r90->>'success')::boolean,false) is not true then raise exception 'Allocation E2E: 90-day RPC failed: %',r90; end if;
  if coalesce((r100->>'success')::boolean,false) is not true then raise exception 'Allocation E2E: 100-day RPC failed: %',r100; end if;
  a90:=(r90->>'allocation_id')::uuid;
  a100:=(r100->>'allocation_id')::uuid;
  if a90=a100 then raise exception 'Allocation E2E: allocation-anchored top-up incorrectly reused the same lot'; end if;
  perform set_config('alloc.a90',a90::text,true);
  perform set_config('alloc.a100',a100::text,true);

  select allocation_valid_days,valid_from,valid_until into d90,vf,vu from public.partner_voucher_allocations where id=a90;
  if d90<>90 or vu<>vf+interval '90 days' then raise exception 'Allocation E2E: 90-day lot clock mismatch'; end if;
  select allocation_valid_days,valid_from,valid_until into d100,vf,vu from public.partner_voucher_allocations where id=a100;
  if d100<>100 or vu<>vf+interval '100 days' then raise exception 'Allocation E2E: 100-day lot clock mismatch'; end if;

  begin
    perform public.admin_engine_allocate_v2(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'dddddddd-2222-4222-8222-dddddddddddd',1,'allocation',0,null
    );
    raise exception 'Allocation E2E: zero-day allocation was accepted';
  exception when others then
    if sqlerrm='Allocation E2E: zero-day allocation was accepted' then raise; end if;
    if position('at least 1' in sqlerrm)=0 then raise exception 'Allocation E2E: unexpected zero-day rejection: %',sqlerrm; end if;
  end;
end;
$$;

-- Partner issuance must consume the earlier-expiring 90-day lot first.
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_id uuid;
  v_allocation uuid;
  v_count integer;
begin
  r:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer One','0128000001');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Allocation E2E: first issue failed: %',r; end if;
  v_id:=(r->>'voucher_id')::uuid;
  select allocation_id into v_allocation from public.vouchers where id=v_id;
  if v_allocation<>current_setting('alloc.a90')::uuid then raise exception 'Allocation E2E: FEFO did not consume 90-day lot first'; end if;
  select count(*) into v_count from public.voucher_branches where voucher_id=v_id;
  if v_count<1 then raise exception 'Allocation E2E: all-branches issue did not materialise branch IDs'; end if;
  perform set_config('alloc.first_voucher',v_id::text,true);
  perform set_config('alloc.first_branch_count',v_count::text,true);
end;
$$;

-- A branch created after issuance must never be retroactively added to the old Voucher.
reset role;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);
insert into public.branches(id,branch_code,branch_name,address,phone,status)
values('dddddddd-9999-4999-8999-dddddddddddd','FUTURE_TEST','Future Test Branch','Future address','03-99999999','active');

do $$
declare v_count integer;
begin
  select count(*) into v_count from public.voucher_branches
  where voucher_id=current_setting('alloc.first_voucher')::uuid
    and branch_id='dddddddd-9999-4999-8999-dddddddddddd';
  if v_count<>0 then raise exception 'Allocation E2E: newly-added branch leaked into old all-branches Voucher'; end if;
  select count(*) into v_count from public.voucher_branches where voucher_id=current_setting('alloc.first_voucher')::uuid;
  if v_count<>current_setting('alloc.first_branch_count')::integer then raise exception 'Allocation E2E: old branch snapshot cardinality changed after branch creation'; end if;
end;
$$;

-- The next issuance is allowed to see the new active branch, but must consume
-- the remaining 100-day lot. This proves snapshot-at-issuance rather than a
-- forever-dynamic all-branches interpretation.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_id uuid;
  v_allocation uuid;
  v_count integer;
begin
  r:=public.issue_engine_voucher('dddddddd-2222-4222-8222-dddddddddddd','FEFO Customer Two','0128000002');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Allocation E2E: second issue failed: %',r; end if;
  v_id:=(r->>'voucher_id')::uuid;
  select allocation_id into v_allocation from public.vouchers where id=v_id;
  if v_allocation<>current_setting('alloc.a100')::uuid then raise exception 'Allocation E2E: second issue did not consume remaining 100-day lot'; end if;
  select count(*) into v_count from public.voucher_branches
  where voucher_id=v_id and branch_id='dddddddd-9999-4999-8999-dddddddddddd';
  if v_count<>1 then raise exception 'Allocation E2E: new issuance did not snapshot newly-active branch'; end if;
end;
$$;

reset role;
rollback;
