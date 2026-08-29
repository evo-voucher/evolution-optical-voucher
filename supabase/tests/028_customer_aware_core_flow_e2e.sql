-- Customer-aware authenticated core flow E2E.
-- This is the canonical CI contract after browser issuance moved behind
-- issue_engine_voucher_with_customer(...). All fixtures roll back.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('a1111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','current-e2e-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('a2222222-2222-4222-8222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','current-e2e-partner-a@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('a3333333-3333-4333-8333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','current-e2e-partner-b@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('a4444444-4444-4444-8444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','current-e2e-staff@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"a1111111-1111-4111-8111-111111111111","role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values('a1111111-1111-4111-8111-111111111111','Current E2E Admin','active');

insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values
('aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa','CURRENT-A','Current Partner A',10,5,true,'active'),
('bb222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb','CURRENT-B','Current Partner B',10,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values
('a2222222-2222-4222-8222-222222222222','aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa','partner_admin','active','Partner A Admin','current-e2e-partner-a@example.invalid'),
('a3333333-3333-4333-8333-333333333333','bb222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb','partner_admin','active','Partner B Admin','current-e2e-partner-b@example.invalid');

insert into public.staff_users(user_id,branch_id,staff_name,role,status)
select 'a4444444-4444-4444-8444-444444444444',b.id,'Current Mines Staff','staff','active'
from public.branches b where b.branch_code='MINES';

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values
('aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false,'a1111111-1111-4111-8111-111111111111'),
('bb222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false,'a1111111-1111-4111-8111-111111111111');

insert into public.partner_claim_branches(partner_id,branch_id)
select 'aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',id from public.branches where branch_code='MINES';
insert into public.partner_claim_branches(partner_id,branch_id)
select 'bb222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb',id from public.branches where branch_code='BAHAU';

insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,created_by)
values('aa111111-1111-4111-8111-aaaaaaaaaaaa','CURRENT-RM60','Current RM60 Voucher','promotion','active','default','a1111111-1111-4111-8111-111111111111');

insert into public.voucher_versions(id,template_id,version_no,version_name,face_value,validity_mode,valid_months,usage_limit,supply_limit,all_branches,status,effective_from,created_by)
values('aa111111-2222-4222-8222-aaaaaaaaaaaa','aa111111-1111-4111-8111-aaaaaaaaaaaa',1,'Current v1',60,'months',3,1,10,false,'active',now(),'a1111111-1111-4111-8111-111111111111');

insert into public.voucher_version_branches(version_id,branch_id)
select 'aa111111-2222-4222-8222-aaaaaaaaaaaa',id from public.branches where branch_code='MINES';

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
values
('aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aa111111-1111-4111-8111-aaaaaaaaaaaa','active','allocation','a1111111-1111-4111-8111-111111111111'),
('bb222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aa111111-1111-4111-8111-aaaaaaaaaaaa','active','allocation','a1111111-1111-4111-8111-111111111111');

insert into public.partner_voucher_allocations(id,partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,validity_value,validity_unit,created_by)
values('aa111111-3333-4333-8333-aaaaaaaaaaaa','aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aa111111-2222-4222-8222-aaaaaaaaaaaa',2,0,'active','issue',3,'months','a1111111-1111-4111-8111-111111111111');

-- Security contract: browser/authenticated clients must not execute the legacy
-- primitive, and the customer-aware wrapper must be executable.
do $$
begin
  if has_function_privilege('authenticated','public.issue_engine_voucher(uuid,text,text,uuid)','EXECUTE') then
    raise exception 'Current E2E: authenticated still has legacy issuance EXECUTE';
  end if;
  if not has_function_privilege('authenticated','public.issue_engine_voucher_with_customer(uuid,text,text,uuid,date,text)','EXECUTE') then
    raise exception 'Current E2E: authenticated lacks customer-aware issuance EXECUTE';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a2222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
do $$
declare r jsonb; c integer; share jsonb;
begin
  r:=public.issue_engine_voucher_with_customer(
    'aa111111-2222-4222-8222-aaaaaaaaaaaa','Current Customer','0123456789',null,'1990-01-01','Kuala Lumpur'
  );
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Current E2E: issuance failed: %',r; end if;
  if (r->>'partner_id')::uuid<>'aa111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid then raise exception 'Current E2E: tenant mismatch'; end if;
  if nullif(r->>'customer_id','') is null then raise exception 'Current E2E: customer master missing'; end if;
  select count(*) into c from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=(r->>'voucher_id')::uuid and b.branch_code='MINES';
  if c<>1 then raise exception 'Current E2E: MINES branch snapshot missing'; end if;
  share:=public.get_partner_voucher_share((r->>'voucher_id')::uuid);
  if position('The Mines' in coalesce(share->>'message_body',''))=0 then raise exception 'Current E2E: share content missing The Mines'; end if;
  perform set_config('current_e2e.voucher_code',r->>'voucher_code',true);
  perform set_config('current_e2e.public_token',r->>'public_token',true);
  perform set_config('current_e2e.voucher_id',r->>'voucher_id',true);
end;
$$;

select set_config('request.jwt.claims','{"sub":"a3333333-3333-4333-8333-333333333333","role":"authenticated"}',true);
do $$
declare blocked boolean:=false; c integer;
begin
  begin
    perform public.issue_engine_voucher_with_customer('aa111111-2222-4222-8222-aaaaaaaaaaaa','Illegal B','0199999999',null,null,'Kuala Lumpur');
  exception when others then
    if position('No active allocation' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'Current E2E: Partner B issued without allocation'; end if;
  select count(*) into c from public.vouchers where id=current_setting('current_e2e.voucher_id')::uuid;
  if c<>0 then raise exception 'Current E2E: Partner B RLS leak'; end if;
end;
$$;

select set_config('request.jwt.claims','{"sub":"a4444444-4444-4444-8444-444444444444","role":"authenticated"}',true);
do $$
declare r jsonb;
begin
  r:=public.verify_voucher(current_setting('current_e2e.voucher_code'),'BAHAU');
  if coalesce((r->>'success')::boolean,false) is not true or coalesce((r->>'can_redeem')::boolean,false) is not true then raise exception 'Current E2E: staff verify failed: %',r; end if;
  if r->>'branch_name'<>'The Mines' then raise exception 'Current E2E: staff branch override succeeded'; end if;
  r:=public.redeem_voucher(current_setting('current_e2e.voucher_code'),'Current redemption','BAHAU','qr');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Current E2E: redemption failed: %',r; end if;
  if r->>'branch_name'<>'The Mines' then raise exception 'Current E2E: redemption used wrong branch'; end if;
  perform set_config('current_e2e.redemption_id',r->>'redemption_id',true);
  r:=public.redeem_voucher(current_setting('current_e2e.voucher_code'),'duplicate',null,'qr');
  if coalesce((r->>'success')::boolean,false) is true then raise exception 'Current E2E: duplicate redemption succeeded'; end if;
end;
$$;

reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
do $$
declare r jsonb;
begin
  r:=public.get_public_voucher(current_setting('current_e2e.public_token')::uuid);
  if r is null then raise exception 'Current E2E: public lookup returned null'; end if;
  if r->>'customer_name'<>'C***' then
    raise exception 'Current E2E: public customer name was not masked: %',r->>'customer_name';
  end if;
  if r ? 'customer_phone' or r ? 'issued_by_user_id' or r ? 'allocation_id' or r ? 'metadata' or r ? 'customer_id' then
    raise exception 'Current E2E: public response leaked private fields: %',r;
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
do $$
declare r jsonb; v_status text; v_usage integer; r_status text;
begin
  r:=public.reverse_redemption(current_setting('current_e2e.redemption_id')::uuid,'Current controlled reversal');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Current E2E: reversal failed: %',r; end if;
  select status,usage_count into v_status,v_usage from public.vouchers where id=current_setting('current_e2e.voucher_id')::uuid;
  if v_status<>'active' or v_usage<>0 then raise exception 'Current E2E: voucher not restored'; end if;
  select status into r_status from public.redemptions where id=current_setting('current_e2e.redemption_id')::uuid;
  if r_status<>'reversed' then raise exception 'Current E2E: redemption history not preserved'; end if;
end;
$$;

reset role;
rollback;
