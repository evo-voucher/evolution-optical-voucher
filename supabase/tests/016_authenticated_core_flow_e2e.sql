-- Auth-context Core Flow E2E v1
-- Runs inside the disposable local Supabase database used by GitHub Actions.
-- Uses real auth.users rows plus Supabase request.jwt.claims / database roles so
-- auth.uid(), auth.jwt(), RLS and authenticated RPC grants execute in user context.
-- The entire fixture rolls back.

begin;

-- Fixed disposable Auth identities.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('11111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e2e-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('22222222-2222-4222-8222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e2e-partner-a@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('33333333-3333-4333-8333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e2e-partner-b@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('44444444-4444-4444-8444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e2e-staff@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

-- Trusted server context for fixture provisioning. This mirrors server-side setup;
-- browser tests below switch to authenticated/anon roles explicitly.
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values('11111111-1111-4111-8111-111111111111','E2E Admin','active');

insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','E2E-A','E2E Partner A',10,5,true,'active'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','E2E-B','E2E Partner B',10,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values
('22222222-2222-4222-8222-222222222222','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','partner_admin','active','Partner A Admin','e2e-partner-a@example.invalid'),
('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','partner_admin','active','Partner B Admin','e2e-partner-b@example.invalid');

insert into public.staff_users(user_id,branch_id,staff_name,role,status)
select '44444444-4444-4444-8444-444444444444',b.id,'E2E Mines Staff','staff','active'
from public.branches b where b.branch_code='MINES';

-- Verify the canonical realm registry blocks the same Auth identity from becoming
-- live Partner + Staff at once.
do $$
declare v_blocked boolean:=false;
begin
  begin
    insert into public.staff_users(user_id,branch_id,staff_name,role,status)
    select '22222222-2222-4222-8222-222222222222',b.id,'Illegal Dual Realm','staff','active'
    from public.branches b where b.branch_code='MINES';
  exception when others then
    if position('different active operational realm' in sqlerrm)>0 then
      v_blocked:=true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'E2E: dual operational realm was not rejected'; end if;
end;
$$;

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false,'11111111-1111-4111-8111-111111111111'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false,'11111111-1111-4111-8111-111111111111');

insert into public.partner_claim_branches(partner_id,branch_id)
select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',id from public.branches where branch_code='MINES';
insert into public.partner_claim_branches(partner_id,branch_id)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',id from public.branches where branch_code='BAHAU';

insert into public.voucher_templates(id,template_code,template_name,voucher_category,status,theme_code,created_by)
values('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','E2E-RM60','E2E RM60 Voucher','promotion','active','default','11111111-1111-4111-8111-111111111111');

insert into public.voucher_versions(id,template_id,version_no,version_name,face_value,validity_mode,valid_months,usage_limit,supply_limit,all_branches,status,effective_from,created_by)
values('aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',1,'E2E v1',60,'months',3,1,10,false,'active',now(),'11111111-1111-4111-8111-111111111111');

insert into public.voucher_version_branches(version_id,branch_id)
select 'aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa',id from public.branches where branch_code='MINES';

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','active','allocation','11111111-1111-4111-8111-111111111111'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','active','allocation','11111111-1111-4111-8111-111111111111');

-- Only Partner A receives allocation. Partner B has product access but no capacity.
insert into public.partner_voucher_allocations(id,partner_id,version_id,quantity_allocated,quantity_revoked,status,created_by)
values('aaaaaaaa-3333-4333-8333-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa',2,0,'active','11111111-1111-4111-8111-111111111111');

-- Partner A authenticated issuance. Tenant comes from auth.uid(), never input.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
do $$
declare r jsonb;
begin
  r:=public.issue_engine_voucher('aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa','E2E Customer','0123456789');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'E2E: Partner A issuance failed: %',r; end if;
  if (r->>'partner_id')::uuid <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid then raise exception 'E2E: issuance tenant was not Auth-derived Partner A'; end if;
  perform set_config('e2e.voucher_code',r->>'voucher_code',true);
  perform set_config('e2e.public_token',r->>'public_token',true);
end;
$$;

-- Owning Partner can see exactly its issued fixture Voucher through RLS.
do $$
declare c integer;
begin
  select count(*) into c from public.vouchers where customer_name='E2E Customer';
  if c<>1 then raise exception 'E2E: Partner A RLS expected 1 own Voucher, got %',c; end if;
end;
$$;

-- Partner B cannot issue A's capacity and cannot read A's Voucher.
select set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}',true);
do $$
declare v_blocked boolean:=false; c integer;
begin
  begin
    perform public.issue_engine_voucher('aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa','Illegal Partner B Issue',null);
  exception when others then
    if position('No active allocation' in sqlerrm)>0 then v_blocked:=true; else raise; end if;
  end;
  if not v_blocked then raise exception 'E2E: Partner B issued without its own allocation'; end if;
  select count(*) into c from public.vouchers where customer_name='E2E Customer';
  if c<>0 then raise exception 'E2E: Partner B RLS leaked Partner A Voucher'; end if;
end;
$$;

-- Evolution Staff verifies and redeems at its server-derived MINES branch.
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}',true);
do $$
declare r jsonb;
begin
  r:=public.verify_voucher(current_setting('e2e.voucher_code'),'BAHAU');
  -- Normal staff branch is server-derived; caller-supplied BAHAU must not override MINES.
  if coalesce((r->>'success')::boolean,false) is not true or coalesce((r->>'can_redeem')::boolean,false) is not true then
    raise exception 'E2E: Staff verify failed: %',r;
  end if;
  if r->>'branch_name' <> 'The Mines' then raise exception 'E2E: normal Staff branch was overridden by caller input: %',r; end if;

  r:=public.redeem_voucher(current_setting('e2e.voucher_code'),'E2E redemption','BAHAU','qr');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'E2E: redemption failed: %',r; end if;
  if r->>'branch_name' <> 'The Mines' then raise exception 'E2E: redemption used wrong branch: %',r; end if;
  perform set_config('e2e.redemption_id',r->>'redemption_id',true);

  r:=public.redeem_voucher(current_setting('e2e.voucher_code'),'duplicate attempt',null,'qr');
  if coalesce((r->>'success')::boolean,false) is true then raise exception 'E2E: duplicate single-use redemption succeeded'; end if;
end;
$$;

-- Public customer lookup works only through random public_token and is read-only.
reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
do $$
declare r jsonb;
begin
  r:=public.get_public_voucher(current_setting('e2e.public_token')::uuid);
  if r is null then raise exception 'E2E: public Voucher lookup returned null'; end if;
  if r ? 'customer_phone' or r ? 'issued_by_user_id' or r ? 'allocation_id' or r ? 'metadata' then
    raise exception 'E2E: public Voucher response leaked sensitive/internal fields: %',r;
  end if;
end;
$$;

-- Admin reverses the Redemption; history remains and Voucher returns active.
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
do $$
declare r jsonb; v_status text; v_usage integer; r_status text;
begin
  r:=public.reverse_redemption(current_setting('e2e.redemption_id')::uuid,'E2E controlled reversal');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'E2E: Admin reversal failed: %',r; end if;
  select status,usage_count into v_status,v_usage from public.vouchers where voucher_code=current_setting('e2e.voucher_code');
  if v_status<>'active' or v_usage<>0 then raise exception 'E2E: Voucher not restored after reversal: status %, usage %',v_status,v_usage; end if;
  select status into r_status from public.redemptions where id=current_setting('e2e.redemption_id')::uuid;
  if r_status<>'reversed' then raise exception 'E2E: Redemption history was not preserved as reversed'; end if;
end;
$$;

reset role;
rollback;
