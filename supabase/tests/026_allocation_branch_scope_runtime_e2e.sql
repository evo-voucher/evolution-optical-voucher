-- Allocation branch scope runtime E2E
-- Proves Admin assignment branch restriction is a first-class third scope:
-- Partner claim ∩ Version scope ∩ Allocation scope.
-- Disposable local CI only; all fixtures roll back.

begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values
('77777777-7777-4777-8777-777777777777','00000000-0000-0000-0000-000000000000','authenticated','authenticated','allocation-admin@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now()),
('88888888-8888-4888-8888-888888888888','00000000-0000-0000-0000-000000000000','authenticated','authenticated','allocation-partner@example.invalid',crypt('test-only',gen_salt('bf')),now(),now(),now());

select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status)
values('77777777-7777-4777-8777-777777777777','Allocation Admin','active');
insert into public.partners(id,partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','ALLOC-P','Allocation Partner',0,5,true,'active');
insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
values('88888888-8888-4888-8888-888888888888','dddddddd-dddd-4ddd-8ddd-dddddddddddd','partner_admin','active','Allocation Partner Admin','allocation-partner@example.invalid');
insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',true,'77777777-7777-4777-8777-777777777777');

-- Admin uses the public RPC boundary to create and publish an all-Version-branches offer.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);

do $$
declare
  v_template uuid;
  v_version uuid;
  a jsonb;
begin
  v_template:=public.admin_create_voucher_template_theme('ALLOC_SCOPE','Allocation Scope Voucher','promotion',null,'classic');
  v_version:=public.admin_publish_voucher_version_v3(
    v_template,'Allocation Scope v1',60,null,'calendar_months_after_issue',null,3,null,
    null,null,1,true,'Allocation scope test',50,true,null,'birthday','{}'::jsonb,'Happy Birthday! 🎂'
  );
  a:=public.admin_engine_allocate_v3(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',v_version,2,'issue',null,false,array['MINES'],null
  );
  if coalesce((a->>'success')::boolean,false) is not true then raise exception 'Allocation scope E2E: allocation failed: %',a; end if;
  if coalesce((a->>'all_branches')::boolean,true) is not false then raise exception 'Allocation scope E2E: allocation did not persist restricted mode'; end if;
  if not exists(
    select 1 from public.partner_voucher_allocation_branches ab
    join public.branches b on b.id=ab.branch_id
    where ab.allocation_id=(a->>'allocation_id')::uuid and b.branch_code='MINES'
  ) then raise exception 'Allocation scope E2E: MINES allocation branch row missing'; end if;
  perform set_config('allocation_scope.version_id',v_version::text,true);
end;
$$;

-- Partner has global all-branch claim and Version is all branches, but the Allocation is MINES-only.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}',true);

do $$
declare
  r jsonb;
  v_id uuid;
  v_count integer;
  s jsonb;
begin
  r:=public.issue_engine_voucher(current_setting('allocation_scope.version_id')::uuid,'Allocation Customer','0120000003');
  if coalesce((r->>'success')::boolean,false) is not true then raise exception 'Allocation scope E2E: issue failed: %',r; end if;
  v_id:=(r->>'voucher_id')::uuid;

  select count(*) into v_count
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=v_id and b.branch_code='MINES';
  if v_count<>1 then raise exception 'Allocation scope E2E: MINES not materialised'; end if;

  select count(*) into v_count
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=v_id and b.branch_code<>'MINES';
  if v_count<>0 then raise exception 'Allocation scope E2E: Allocation restriction was broadened'; end if;

  s:=public.get_partner_voucher_share(v_id);
  if position('The Mines' in coalesce(s->>'message_body',''))=0 then raise exception 'Allocation scope E2E: share missing MINES'; end if;
  if position('Bahau' in coalesce(s->>'message_body',''))>0 then raise exception 'Allocation scope E2E: share leaked BAHAU'; end if;
end;
$$;

reset role;
rollback;
