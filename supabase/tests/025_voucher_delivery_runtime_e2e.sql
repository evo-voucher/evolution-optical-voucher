-- Voucher delivery runtime E2E
-- Proves issue-relative calendar months, allocation-relative batch anchoring,
-- frozen theme/greeting/branch snapshots, and tenant-scoped WhatsApp share content.
-- Runs only in the disposable local CI database and rolls back all fixtures.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('55555555-5555-4555-8555-555555555555','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delivery-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('66666666-6666-4666-8666-666666666666','00000000-0000-0000-0000-000000000000','authenticated','authenticated','delivery-partner@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"55555555-5555-4555-8555-555555555555","role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values('55555555-5555-4555-8555-555555555555','Delivery Admin','active');

insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','DELIVERY-P','Delivery Partner',0,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values('66666666-6666-4666-8666-666666666666','cccccccc-cccc-4ccc-8ccc-cccccccccccc','partner_admin','active','Delivery Partner Admin','delivery-partner@example.invalid');

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values('cccccccc-cccc-4ccc-8ccc-cccccccccccc',false,'55555555-5555-4555-8555-555555555555');
insert into public.partner_claim_branches(partner_id,branch_id)
select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',id from public.branches where branch_code='MINES';

insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,theme_config,created_by)
values('cccccccc-1111-4111-8111-cccccccccccc','DELIVERY','Delivery Voucher','promotion','active','default','{}'::jsonb,'55555555-5555-4555-8555-555555555555');

insert into public.voucher_versions(
  id,template_id,version_no,version_name,face_value,validity_mode,valid_months,
  usage_limit,supply_limit,all_branches,theme_override_code,theme_override_config,
  greeting_text,terms_text,status,effective_from,created_by
) values(
  'cccccccc-2222-4222-8222-cccccccccccc','cccccccc-1111-4111-8111-cccccccccccc',1,'Birthday v1',60,'months',3,
  1,20,false,'birthday','{"occasion":"birthday"}'::jsonb,
  'Happy Birthday! 🎂','Birthday terms','active',now(),'55555555-5555-4555-8555-555555555555'
);
insert into public.voucher_version_branches(version_id,branch_id)
select 'cccccccc-2222-4222-8222-cccccccccccc',id from public.branches where branch_code in ('MINES','BAHAU');

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','cccccccc-1111-4111-8111-cccccccccccc','active','allocation','55555555-5555-4555-8555-555555555555');

insert into public.partner_voucher_allocations(
  id,partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,allocation_valid_days,created_by
) values(
  'cccccccc-3333-4333-8333-cccccccccccc','cccccccc-cccc-4ccc-8ccc-cccccccccccc','cccccccc-2222-4222-8222-cccccccccccc',2,0,'active','issue',null,'55555555-5555-4555-8555-555555555555'
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-4666-8666-666666666666","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_issue_date date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_expected date;
  v_id uuid;
  v_token uuid;
  v_theme text;
  v_greeting text;
  v_anchor text;
  v_value integer;
  v_unit text;
  v_count integer;
begin
  r:=public.issue_engine_voucher('cccccccc-2222-4222-8222-cccccccccccc','Birthday Customer','0120000001');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Delivery E2E: issue-relative issuance failed: %',r; end if;
  v_id:=(r->>'voucher_id')::uuid;
  v_token:=(r->>'public_token')::uuid;
  v_expected:=(v_issue_date+make_interval(months=>3))::date;
  if (r->>'expiry_date')::date<>v_expected then raise exception 'Delivery E2E: calendar-month expiry mismatch, expected %, got %',v_expected,r->>'expiry_date'; end if;

  select theme_code_snapshot,greeting_snapshot,validity_anchor_snapshot,validity_value_snapshot,validity_unit_snapshot
    into v_theme,v_greeting,v_anchor,v_value,v_unit
  from public.vouchers where id=v_id;
  if v_theme<>'birthday' then raise exception 'Delivery E2E: birthday theme not frozen'; end if;
  if position('A little gift for you 🎁✨' in v_greeting)=0 or position('Happy Birthday! 🎂' in v_greeting)=0 then
    raise exception 'Delivery E2E: approved default + occasion greeting not frozen: %',v_greeting;
  end if;
  if v_anchor<>'issue' or v_value<>3 or v_unit<>'months' then raise exception 'Delivery E2E: issue validity snapshot mismatch'; end if;
  select count(*) into v_count from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=v_id and b.branch_code='MINES';
  if v_count<>1 then raise exception 'Delivery E2E: MINES branch was not snapshotted'; end if;
  select count(*) into v_count from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=v_id and b.branch_code='BAHAU';
  if v_count<>0 then raise exception 'Delivery E2E: Partner branch scope was broadened beyond MINES'; end if;
  perform set_config('delivery.issue_voucher_id',v_id::text,true);
  perform set_config('delivery.issue_token',v_token::text,true);
end;
$$;

-- Change the Partner's future claim scope. The already-issued Voucher must remain MINES.
reset role;
select set_config('request.jwt.claims','{"sub":"55555555-5555-4555-8555-555555555555","role":"service_role"}',true);
delete from public.partner_claim_branches where partner_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
insert into public.partner_claim_branches(partner_id,branch_id)
select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',id from public.branches where branch_code='BAHAU';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-4666-8666-666666666666","role":"authenticated"}',true);

do $$
declare s jsonb; p jsonb; v_branches jsonb;
begin
  s:=public.get_partner_voucher_share(current_setting('delivery.issue_voucher_id')::uuid);
  if position('A little gift for you 🎁✨' in coalesce(s->>'message_body',''))=0 then raise exception 'Delivery E2E: share greeting missing: %',s; end if;
  if position('The Mines' in coalesce(s->>'message_body',''))=0 then raise exception 'Delivery E2E: frozen MINES share location missing: %',s; end if;
  if position('Bahau' in coalesce(s->>'message_body',''))>0 then raise exception 'Delivery E2E: later BAHAU claim change leaked into old share: %',s; end if;

  p:=public.get_public_voucher(current_setting('delivery.issue_token')::uuid);
  if p->>'theme_code'<>'birthday' then raise exception 'Delivery E2E: public old theme changed: %',p; end if;
  if position('Happy Birthday! 🎂' in coalesce(p->>'greeting',''))=0 then raise exception 'Delivery E2E: public frozen greeting missing: %',p; end if;
  v_branches:=coalesce(p->'branches','[]'::jsonb);
  if jsonb_array_length(v_branches)<>1 or v_branches->0->>'branch_code'<>'MINES' then raise exception 'Delivery E2E: public branch snapshot changed: %',v_branches; end if;
end;
$$;

-- Add a second Version and an allocation-anchored batch. Later issuance must use
-- the Admin allocation clock, not reset 100 days from issue time.
reset role;
select set_config('request.jwt.claims','{"sub":"55555555-5555-4555-8555-555555555555","role":"service_role"}',true);

insert into public.voucher_versions(
  id,template_id,version_no,version_name,face_value,validity_mode,valid_days,
  usage_limit,supply_limit,all_branches,theme_override_code,theme_override_config,
  greeting_text,terms_text,status,effective_from,created_by
) values(
  'cccccccc-4444-4444-8444-cccccccccccc','cccccccc-1111-4111-8111-cccccccccccc',2,'Raya allocation v2',60,'days',100,
  1,20,false,'raya','{"occasion":"raya"}'::jsonb,
  'Selamat Hari Raya! 🌙✨','Raya terms','active',now(),'55555555-5555-4555-8555-555555555555'
);
insert into public.voucher_version_branches(version_id,branch_id)
select 'cccccccc-4444-4444-8444-cccccccccccc',id from public.branches where branch_code in ('MINES','BAHAU');

insert into public.partner_voucher_allocations(
  id,partner_id,version_id,quantity_allocated,quantity_revoked,status,
  validity_anchor,allocation_valid_days,valid_from,valid_until,created_by
) values(
  'cccccccc-5555-4555-8555-cccccccccccc','cccccccc-cccc-4ccc-8ccc-cccccccccccc','cccccccc-4444-4444-8444-cccccccccccc',1,0,'active',
  'allocation',100,now()-interval '10 days',now()+interval '90 days','55555555-5555-4555-8555-555555555555'
);

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"66666666-6666-4666-8666-666666666666","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_expected date;
  v_id uuid;
  v_anchor text;
  v_value integer;
  v_unit text;
  v_theme text;
  v_count integer;
begin
  select (valid_until at time zone 'Asia/Kuala_Lumpur')::date into v_expected
  from public.partner_voucher_allocations where id='cccccccc-5555-4555-8555-cccccccccccc';
  r:=public.issue_engine_voucher('cccccccc-4444-4444-8444-cccccccccccc','Raya Customer','0120000002');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Delivery E2E: allocation-relative issuance failed: %',r; end if;
  if (r->>'expiry_date')::date<>v_expected then raise exception 'Delivery E2E: allocation expiry reset on issue, expected %, got %',v_expected,r->>'expiry_date'; end if;
  v_id:=(r->>'voucher_id')::uuid;
  select validity_anchor_snapshot,validity_value_snapshot,validity_unit_snapshot,theme_code_snapshot
    into v_anchor,v_value,v_unit,v_theme from public.vouchers where id=v_id;
  if v_anchor<>'allocation' or v_value<>100 or v_unit<>'days' then raise exception 'Delivery E2E: allocation validity snapshot mismatch'; end if;
  if v_theme<>'raya' then raise exception 'Delivery E2E: new Version did not receive Raya theme'; end if;
  select count(*) into v_count from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=v_id and b.branch_code='BAHAU';
  if v_count<>1 then raise exception 'Delivery E2E: new Voucher did not use current BAHAU Partner scope'; end if;
  select count(*) into v_count from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=v_id and b.branch_code='MINES';
  if v_count<>0 then raise exception 'Delivery E2E: new Voucher incorrectly retained old MINES Partner scope'; end if;
end;
$$;

reset role;
rollback;