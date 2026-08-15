-- Partner Staff tenant + branch non-broadening runtime E2E
-- Proves the canonical issue RPC derives Partner identity from Auth,
-- exposes no partner_id override parameter, and materialises only the
-- authenticated Partner's permitted branch intersection.
-- Disposable local CI only; all fixtures roll back.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('77777777-7777-4777-8777-777777777771','00000000-0000-0000-0000-000000000000','authenticated','authenticated','tenant-staff-a@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('77777777-7777-4777-8777-777777777772','00000000-0000-0000-0000-000000000000','authenticated','authenticated','tenant-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777772","role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values('77777777-7777-4777-8777-777777777772','Tenant Test Admin','active');

insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values
('aaaaaaaa-7777-4777-8777-777777777771','TENANT-A','Tenant Partner A',0,5,true,'active'),
('bbbbbbbb-7777-4777-8777-777777777772','TENANT-B','Tenant Partner B',0,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values('77777777-7777-4777-8777-777777777771','aaaaaaaa-7777-4777-8777-777777777771','partner_staff','active','Tenant Staff A','tenant-staff-a@example.invalid');

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values
('aaaaaaaa-7777-4777-8777-777777777771',false,'77777777-7777-4777-8777-777777777772'),
('bbbbbbbb-7777-4777-8777-777777777772',false,'77777777-7777-4777-8777-777777777772');

insert into public.partner_claim_branches(partner_id,branch_id)
select 'aaaaaaaa-7777-4777-8777-777777777771',id from public.branches where branch_code='MINES';
insert into public.partner_claim_branches(partner_id,branch_id)
select 'bbbbbbbb-7777-4777-8777-777777777772',id from public.branches where branch_code='BAHAU';

insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,theme_config,created_by)
values('77777777-1111-4111-8111-777777777771','TENANTSAFE','Tenant Safe Voucher','promotion','active','default','{}'::jsonb,'77777777-7777-4777-8777-777777777772');

insert into public.voucher_versions(
  id,template_id,version_no,version_name,face_value,validity_mode,valid_days,
  usage_limit,supply_limit,all_branches,status,effective_from,created_by
) values(
  '77777777-2222-4222-8222-777777777772','77777777-1111-4111-8111-777777777771',1,'Tenant Safe v1',60,'days',30,
  1,20,false,'active',now(),'77777777-7777-4777-8777-777777777772'
);

insert into public.voucher_version_branches(version_id,branch_id)
select '77777777-2222-4222-8222-777777777772',id from public.branches where branch_code in ('MINES','BAHAU');

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
values
('aaaaaaaa-7777-4777-8777-777777777771','77777777-1111-4111-8111-777777777771','active','allocation','77777777-7777-4777-8777-777777777772'),
('bbbbbbbb-7777-4777-8777-777777777772','77777777-1111-4111-8111-777777777771','active','allocation','77777777-7777-4777-8777-777777777772');

insert into public.partner_voucher_allocations(
  id,partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,created_by
) values
('77777777-3333-4333-8333-777777777771','aaaaaaaa-7777-4777-8777-777777777771','77777777-2222-4222-8222-777777777772',2,0,'active','issue','77777777-7777-4777-8777-777777777772'),
('77777777-3333-4333-8333-777777777772','bbbbbbbb-7777-4777-8777-777777777772','77777777-2222-4222-8222-777777777772',2,0,'active','issue','77777777-7777-4777-8777-777777777772');

-- Canonical public contract must have exactly three business parameters.
do $$
begin
  if to_regprocedure('public.issue_engine_voucher(uuid,text,text)') is null then
    raise exception 'Tenant E2E: canonical issue_engine_voucher(uuid,text,text) missing';
  end if;
  if to_regprocedure('public.issue_engine_voucher(uuid,text,text,uuid)') is not null then
    raise exception 'Tenant E2E: partner override signature unexpectedly exists';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777771","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_id uuid;
  v_partner uuid;
  v_count integer;
  v_override_rejected boolean:=false;
begin
  -- Attempting to invent a browser-supplied Partner override must fail at the function boundary.
  begin
    execute 'select public.issue_engine_voucher($1,$2,$3,$4)'
      using '77777777-2222-4222-8222-777777777772'::uuid,'Override Attempt','0123000000','bbbbbbbb-7777-4777-8777-777777777772'::uuid;
  exception when undefined_function then
    v_override_rejected:=true;
  end;
  if not v_override_rejected then
    raise exception 'Tenant E2E: Partner override call was not rejected';
  end if;

  r:=public.issue_engine_voucher('77777777-2222-4222-8222-777777777772','Tenant Customer','0123000001');
  if coalesce((r->>'success')::boolean,false) is not true then
    raise exception 'Tenant E2E: canonical Partner Staff issuance failed: %',r;
  end if;
  v_id:=(r->>'voucher_id')::uuid;

  select partner_id into v_partner from public.vouchers where id=v_id;
  if v_partner<>'aaaaaaaa-7777-4777-8777-777777777771'::uuid then
    raise exception 'Tenant E2E: issuance escaped authenticated Partner tenant: %',v_partner;
  end if;

  select count(*) into v_count
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=v_id and b.branch_code='MINES';
  if v_count<>1 then raise exception 'Tenant E2E: authenticated Partner MINES branch missing'; end if;

  select count(*) into v_count
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=v_id and b.branch_code='BAHAU';
  if v_count<>0 then raise exception 'Tenant E2E: foreign Partner BAHAU branch broadened into issued Voucher'; end if;

  select count(*) into v_count from public.voucher_branches where voucher_id=v_id;
  if v_count<>1 then raise exception 'Tenant E2E: unexpected issued branch count %',v_count; end if;
end;
$$;

reset role;
rollback;
