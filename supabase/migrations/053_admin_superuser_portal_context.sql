-- Canonical Admin superuser portal context.
-- One durable capability: Admin may use Partner/Staff portals only through explicit,
-- server-validated operational context. Ordinary Partner/Staff behavior remains unchanged.

create or replace function public.resolve_partner_portal_context(p_partner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_partner_user public.partner_users%rowtype;
  v_partner public.partners%rowtype;
  v_admin_name text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select pu.* into v_partner_user
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if found then
    if p_partner_id is not null and p_partner_id<>v_partner_user.partner_id then
      raise exception 'Partner context access denied';
    end if;
    return jsonb_build_object(
      'actor_user_id',v_uid,
      'actor_realm','partner',
      'partner_id',v_partner_user.partner_id,
      'role',v_partner_user.role,
      'actor_name',coalesce(nullif(trim(v_partner_user.staff_name),''),case when v_partner_user.role='partner_admin' then 'Partner Admin' else 'Partner Staff' end),
      'is_admin',false
    );
  end if;

  if public.is_voucher_admin() then
    if p_partner_id is null then raise exception 'Admin must select a Partner'; end if;
    select * into v_partner from public.partners p where p.id=p_partner_id and p.status='active';
    if not found then raise exception 'Active Partner not found'; end if;
    select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
    from public.admin_users a
    where a.user_id=v_uid and a.status='active'
    limit 1;
    return jsonb_build_object(
      'actor_user_id',v_uid,
      'actor_realm','admin',
      'partner_id',v_partner.id,
      'role','admin',
      'actor_name',coalesce(v_admin_name,'Admin'),
      'is_admin',true
    );
  end if;

  raise exception 'Active Partner or Admin account required';
end;
$function$;
revoke all on function public.resolve_partner_portal_context(uuid) from public, anon;
grant execute on function public.resolve_partner_portal_context(uuid) to authenticated;

-- Replace Partner portal RPCs with one explicit request-scoped Partner context.
drop function if exists public.get_my_partner_dashboard();
create function public.get_my_partner_dashboard(p_partner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_role text := v_ctx->>'role';
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,
    'partner_code',p.partner_code,
    'partner_name',p.partner_name,
    'voucher_limit',p.voucher_limit,
    'voucher_limit_unlimited',p.voucher_limit=0,
    'vouchers_issued',(select count(*) from public.vouchers v where v.partner_id=p.id),
    'remaining',case when p.voucher_limit=0 then null else greatest(0,p.voucher_limit-(select count(*) from public.vouchers v where v.partner_id=p.id)) end,
    'partner_status',p.status,
    'role',v_role,
    'staff_name',v_ctx->>'actor_name',
    'staff_access_enabled',p.staff_access_enabled,
    'staff_limit',p.staff_limit,
    'can_issue_voucher',case when v_role in ('partner_admin','admin') then true when v_role='partner_staff' then p.staff_access_enabled else false end,
    'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false)
  ) into v_result
  from public.partners p
  where p.id=v_partner_id and p.status='active';
  if v_result is null then raise exception 'Active Partner not found'; end if;
  return v_result;
end;
$function$;
revoke all on function public.get_my_partner_dashboard(uuid) from public, anon;
grant execute on function public.get_my_partner_dashboard(uuid) to authenticated;

drop function if exists public.get_my_partner_claim_access();
create function public.get_my_partner_claim_access(p_partner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner uuid := (v_ctx->>'partner_id')::uuid;
  v_all boolean := false;
  v_branches jsonb := '[]'::jsonb;
  v_branch_codes text[] := '{}'::text[];
  v_branch_names text[] := '{}'::text[];
begin
  select coalesce(s.all_branches,false) into v_all from public.partner_claim_settings s where s.partner_id=v_partner;
  if not found then v_all:=false; end if;
  select
    coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
    coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]),
    coalesce(array_agg(b.branch_name order by b.branch_name),'{}'::text[])
  into v_branches,v_branch_codes,v_branch_names
  from public.partner_claim_branches pcb
  join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=v_partner and b.status='active';
  return jsonb_build_object('success',true,'partner_id',v_partner,'all_branches',v_all,'branch_codes',v_branch_codes,'branch_names',v_branch_names,'branches',v_branches);
end;
$function$;
revoke all on function public.get_my_partner_claim_access(uuid) from public, anon;
grant execute on function public.get_my_partner_claim_access(uuid) to authenticated;

drop function if exists public.partner_voucher_summary();
create function public.partner_voucher_summary(p_partner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',v_partner_id,
    'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
    'active_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='active' and v.expiry_date>=v_today and v.usage_count<v.usage_limit),
    'redeemed_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and not (v.status='expired' or (v.status='active' and v.expiry_date<v_today)) and v.usage_count>=v.usage_limit),
    'expired_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))),
    'revoked_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='revoked'),
    'completed_redemptions',(select count(*) from public.redemptions r where r.partner_id=v_partner_id and r.status='completed')
  ) into v_result;
  return v_result;
end;
$function$;
revoke all on function public.partner_voucher_summary(uuid) from public, anon;
grant execute on function public.partner_voucher_summary(uuid) to authenticated;

drop function if exists public.partner_recent_vouchers(integer);
create function public.partner_recent_vouchers(p_limit integer default 50,p_partner_id uuid default null)
returns table(voucher_id uuid,voucher_code text,customer_name text,customer_phone text,voucher_type text,voucher_status text,expiry_date date,issued_at timestamptz,issued_by_name text,usage_count integer,usage_limit integer,last_redeemed_at timestamptz,last_branch_name text)
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
begin
  if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500'; end if;
  return query
  select v.id,v.voucher_code,v.customer_name,v.customer_phone,v.voucher_type,
    case when v.status='revoked' then 'revoked' when v.status='expired' or (v.status='active' and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired' when v.usage_count>=v.usage_limit then 'redeemed' else 'active' end,
    v.expiry_date,v.issued_at,v.issued_by_name,v.usage_count,v.usage_limit,lr.redeemed_at,lr.branch_name
  from public.vouchers v
  left join lateral (
    select r.redeemed_at,b.branch_name
    from public.redemptions r join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id and r.status='completed'
    order by r.redeemed_at desc limit 1
  ) lr on true
  where v.partner_id=v_partner_id
  order by v.issued_at desc
  limit p_limit;
end;
$function$;
revoke all on function public.partner_recent_vouchers(integer,uuid) from public, anon;
grant execute on function public.partner_recent_vouchers(integer,uuid) to authenticated;

drop function if exists public.partner_staff_directory();
create function public.partner_staff_directory(p_partner_id uuid default null)
returns table(staff_id uuid,user_id uuid,staff_name text,login_email text,staff_status text,created_at timestamptz,updated_at timestamptz,removed_at timestamptz)
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_role text := v_ctx->>'role';
begin
  if v_role not in ('partner_admin','admin') then raise exception 'Partner Admin or Admin access required'; end if;
  return query
  select pu.id,pu.user_id,pu.staff_name,pu.login_email,pu.status,pu.created_at,pu.updated_at,pu.removed_at
  from public.partner_users pu
  where pu.partner_id=v_partner_id and pu.role='partner_staff'
  order by (pu.removed_at is not null),lower(coalesce(pu.staff_name,'')),pu.created_at;
end;
$function$;
revoke all on function public.partner_staff_directory(uuid) from public, anon;
grant execute on function public.partner_staff_directory(uuid) to authenticated;

drop function if exists public.partner_issuable_voucher_catalog();
create function public.partner_issuable_voucher_catalog(p_partner_id uuid default null)
returns table(version_id uuid,template_id uuid,template_code text,template_name text,version_no integer,version_name text,voucher_label text,face_value numeric,discount_percent numeric,validity_mode text,valid_days integer,valid_months integer,valid_until date,usage_limit integer,transferable boolean,terms_text text,remaining_allocation bigint,remaining_supply bigint)
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_role text := v_ctx->>'role';
  v_staff_access_enabled boolean;
  v_partner_limit integer;
  v_partner_issued bigint;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select p.staff_access_enabled,p.voucher_limit into v_staff_access_enabled,v_partner_limit from public.partners p where p.id=v_partner_id and p.status='active';
  if not found then raise exception 'Active Partner not found'; end if;
  if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;
  select count(*) into v_partner_issued from public.vouchers v where v.partner_id=v_partner_id;
  if coalesce(v_partner_limit,0)>0 and v_partner_issued>=v_partner_limit then return; end if;
  return query
  select vv.id,vt.id,vt.template_code,vt.template_name,vv.version_no,vv.version_name,
    case when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))||' '||vt.template_name when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'% '||vt.template_name else vt.template_name end,
    vv.face_value,vv.discount_percent,vv.validity_mode,vv.valid_days,vv.valid_months,vv.valid_until,vv.usage_limit,vv.transferable,vv.terms_text,
    alloc.remaining_allocation,
    case when vv.supply_limit is null then null else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint end
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id and vt.status='active'
  join public.partner_voucher_access pva on pva.partner_id=v_partner_id and pva.template_id=vv.template_id and pva.status='active' and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())
  join lateral (
    select coalesce(sum(greatest(0,(pa.quantity_allocated-pa.quantity_revoked)-coalesce(ai.issued_count,0))),0)::bigint as remaining_allocation
    from public.partner_voucher_allocations pa
    left join lateral (select count(*)::bigint as issued_count from public.vouchers vx where vx.allocation_id=pa.id) ai on true
    where pa.partner_id=v_partner_id and pa.version_id=vv.id and pa.status='active' and (pa.valid_from is null or pa.valid_from<=now()) and (pa.valid_until is null or pa.valid_until>=now())
  ) alloc on alloc.remaining_allocation>0
  left join lateral (select count(*)::bigint as issued_count from public.vouchers vx where vx.version_id=vv.id) vi on true
  where vv.status='active'
    and (vv.validity_mode<>'fixed' or ((vv.valid_from is null or vv.valid_from<=v_today) and vv.valid_until is not null and vv.valid_until>=v_today))
    and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
  order by vt.template_name,vv.version_no desc;
end;
$function$;
revoke all on function public.partner_issuable_voucher_catalog(uuid) from public, anon;
grant execute on function public.partner_issuable_voucher_catalog(uuid) to authenticated;

drop function if exists public.issue_engine_voucher(uuid,text,text);
create function public.issue_engine_voucher(p_version_id uuid,p_customer_name text,p_customer_phone text default null,p_partner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_partner_role text := v_ctx->>'role';
  v_staff_name text := v_ctx->>'actor_name';
  v_staff_access_enabled boolean;
  v_template public.voucher_templates%rowtype;
  v_version public.voucher_versions%rowtype;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_issued integer:=0;
  v_issue_date date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_expiry_date date;
  v_partner_all_branches boolean:=false;
  v_final_all_branches boolean:=false;
  v_voucher_id uuid;
  v_voucher_code text;
  v_public_token uuid;
  v_voucher_type text;
  v_branch_count integer:=0;
begin
  if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Customer name is required'; end if;
  select p.staff_access_enabled into v_staff_access_enabled from public.partners p where p.id=v_partner_id and p.status='active';
  if not found then raise exception 'Active Partner not found'; end if;
  if v_partner_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;
  select * into v_version from public.voucher_versions vv where vv.id=p_version_id and vv.status='active' limit 1;
  if not found then raise exception 'Active voucher version not found'; end if;
  select * into v_template from public.voucher_templates vt where vt.id=v_version.template_id and vt.status='active' limit 1;
  if not found then raise exception 'Active voucher template not found'; end if;
  if not exists(select 1 from public.partner_voucher_access pva where pva.partner_id=v_partner_id and pva.template_id=v_template.id and pva.status='active' and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())) then raise exception 'This Partner is not authorised for this voucher type'; end if;
  select a.* into v_allocation from public.partner_voucher_allocations a
  where a.partner_id=v_partner_id and a.version_id=p_version_id and a.status='active' and (a.valid_from is null or a.valid_from<=now()) and (a.valid_until is null or a.valid_until>=now())
    and (a.quantity_allocated-a.quantity_revoked)>(select count(*) from public.vouchers vx where vx.allocation_id=a.id)
  order by case when a.validity_anchor='allocation' then 0 else 1 end,case when a.validity_anchor='allocation' then a.valid_until end asc nulls last,a.created_at asc
  limit 1 for update of a;
  if not found then raise exception 'No active allocation is available for this voucher type'; end if;
  select count(*) into v_issued from public.vouchers v where v.allocation_id=v_allocation.id;
  if v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued<=0 then raise exception 'Voucher allocation limit reached'; end if;
  if v_version.supply_limit is not null and (select count(*) from public.vouchers v where v.version_id=v_version.id)>=v_version.supply_limit then raise exception 'Voucher version supply limit reached'; end if;
  if v_allocation.validity_anchor='allocation' then
    if v_allocation.valid_until is null then raise exception 'Allocation expiry is not configured'; end if;
    v_expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
  else
    case v_version.validity_mode
      when 'fixed' then if v_version.valid_from is not null and v_issue_date<v_version.valid_from then raise exception 'Voucher campaign has not started'; end if; if v_version.valid_until is null or v_issue_date>v_version.valid_until then raise exception 'Voucher campaign has ended'; end if; v_expiry_date:=v_version.valid_until;
      when 'days' then v_expiry_date:=v_issue_date+v_version.valid_days;
      when 'months' then v_expiry_date:=(v_issue_date+make_interval(months=>v_version.valid_months))::date;
      else raise exception 'Voucher validity is not configured';
    end case;
  end if;
  select coalesce(s.all_branches,false) into v_partner_all_branches from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=false; end if;
  v_final_all_branches:=v_partner_all_branches and v_version.all_branches;
  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case when v_version.face_value is not null then 'RM'||trim(to_char(v_version.face_value,'FM999999990.##'))||' '||v_template.template_name when v_version.discount_percent is not null then trim(to_char(v_version.discount_percent,'FM999999990.##'))||'% '||v_template.template_name else v_template.template_name end;
  insert into public.vouchers(voucher_code,partner_id,customer_name,customer_phone,voucher_type,status,expiry_date,issued_by_user_id,issued_by_name,all_branches,usage_limit,usage_count,template_id,version_id,allocation_id,metadata,branch_scope_snapshotted)
  values(v_voucher_code,v_partner_id,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,'active',v_expiry_date,v_uid,v_staff_name,v_final_all_branches,v_version.usage_limit,0,v_template.id,v_version.id,v_allocation.id,jsonb_build_object('issuance_path','engine','template_code',v_template.template_code,'version_no',v_version.version_no,'actor_realm',v_ctx->>'actor_realm'),false)
  returning id,public_token,expiry_date into v_voucher_id,v_public_token,v_expiry_date;
  if v_partner_all_branches and v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id) select v_voucher_id,b.id from public.branches b where b.status='active';
  elsif not v_partner_all_branches and v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id) select v_voucher_id,pcb.branch_id from public.partner_claim_branches pcb join public.branches b on b.id=pcb.branch_id where pcb.partner_id=v_partner_id and b.status='active';
  elsif v_partner_all_branches and not v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id) select v_voucher_id,vvb.branch_id from public.voucher_version_branches vvb join public.branches b on b.id=vvb.branch_id where vvb.version_id=v_version.id and b.status='active';
  else
    insert into public.voucher_branches(voucher_id,branch_id) select v_voucher_id,pcb.branch_id from public.partner_claim_branches pcb join public.voucher_version_branches vvb on vvb.branch_id=pcb.branch_id join public.branches b on b.id=pcb.branch_id where pcb.partner_id=v_partner_id and vvb.version_id=v_version.id and b.status='active';
  end if;
  select count(*) into v_branch_count from public.voucher_branches vb where vb.voucher_id=v_voucher_id;
  if v_branch_count=0 then raise exception 'No valid redemption branch is shared by Partner and Voucher Version'; end if;
  update public.vouchers set branch_scope_snapshotted=true,updated_at=now() where id=v_voucher_id;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,v_staff_name,'engine_voucher_issued','voucher',v_voucher_id::text,v_partner_id,jsonb_build_object('voucher_code',v_voucher_code,'template_code',v_template.template_code,'version_no',v_version.version_no,'validity_anchor',v_allocation.validity_anchor,'expiry_date',v_expiry_date,'branch_snapshot_count',v_branch_count),jsonb_build_object('allocation_id',v_allocation.id,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),'actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'voucher_id',v_voucher_id,'voucher_code',v_voucher_code,'public_token',v_public_token,'partner_id',v_partner_id,'template_id',v_template.id,'template_code',v_template.template_code,'template_name',v_template.template_name,'version_id',v_version.id,'version_no',v_version.version_no,'version_name',v_version.version_name,'voucher_type',v_voucher_type,'expiry_date',v_expiry_date,'validity_anchor',v_allocation.validity_anchor,'all_branches',v_final_all_branches,'branch_snapshot_count',v_branch_count,'usage_limit',v_version.usage_limit,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),'theme_code',coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default'),'theme_config',case when nullif(v_version.theme_override_code,'') is not null then v_version.theme_override_config else v_template.theme_config end,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.issue_engine_voucher(uuid,text,text,uuid) from public, anon;
grant execute on function public.issue_engine_voucher(uuid,text,text,uuid) to authenticated;

-- Staff portal resolver: staff uses assigned identity, Admin is a superuser and must select branch for operations.
create or replace function public.resolve_staff_portal_context()
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_admin_name text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select * into v_staff from public.staff_users su where su.user_id=v_uid and su.status='active' limit 1;
  if found then
    return jsonb_build_object('actor_user_id',v_uid,'actor_realm','staff','staff_name',v_staff.staff_name,'role',v_staff.role,'branch_id',v_staff.branch_id,'is_admin',false);
  end if;
  if public.is_voucher_admin() then
    select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name from public.admin_users a where a.user_id=v_uid and a.status='active' limit 1;
    return jsonb_build_object('actor_user_id',v_uid,'actor_realm','admin','staff_name',coalesce(v_admin_name,'Admin'),'role','admin','branch_id',null,'is_admin',true);
  end if;
  raise exception 'Active Staff or Admin account required';
end;
$function$;
revoke all on function public.resolve_staff_portal_context() from public, anon;
grant execute on function public.resolve_staff_portal_context() to authenticated;

create or replace function public.staff_operational_context()
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_role text := v_ctx->>'role';
  v_branch_id uuid := nullif(v_ctx->>'branch_id','')::uuid;
  v_branch public.branches%rowtype;
  v_branches jsonb := '[]'::jsonb;
begin
  if v_role in ('all_branch_manager','admin') then
    select coalesce(jsonb_agg(jsonb_build_object('branch_id',b.id,'branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb)
    into v_branches from public.branches b where b.status='active';
  else
    if v_branch_id is null then raise exception 'Staff account has no branch assigned'; end if;
    select * into v_branch from public.branches b where b.id=v_branch_id and b.status='active';
    if not found then raise exception 'Assigned branch is not active'; end if;
    v_branches:=jsonb_build_array(jsonb_build_object('branch_id',v_branch.id,'branch_code',v_branch.branch_code,'branch_name',v_branch.branch_name,'address',v_branch.address,'phone',v_branch.phone));
  end if;
  return jsonb_build_object('success',true,'staff_user_id',(v_ctx->>'actor_user_id')::uuid,'staff_name',v_ctx->>'staff_name','role',v_role,'branch_id',v_branch_id,'branch_selection_required',v_role in ('all_branch_manager','admin'),'branches',v_branches,'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false));
end;
$function$;
revoke all on function public.staff_operational_context() from public, anon;
grant execute on function public.staff_operational_context() to authenticated;

create or replace function public.staff_today_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_uid uuid := (v_ctx->>'actor_user_id')::uuid;
  v_role text := v_ctx->>'role';
  v_branch_id uuid := nullif(v_ctx->>'branch_id','')::uuid;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_count bigint;
begin
  select count(*) into v_count
  from public.redemptions r
  where r.status='completed'
    and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
    and (v_role in ('all_branch_manager','admin') or (v_role='manager' and r.branch_id=v_branch_id) or (v_role='staff' and r.staff_user_id=v_uid));
  return jsonb_build_object('success',true,'staff_user_id',v_uid,'staff_name',v_ctx->>'staff_name','role',v_role,'branch_id',v_branch_id,'today_redeemed',v_count,'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false));
end;
$function$;
revoke all on function public.staff_today_summary() from public, anon;
grant execute on function public.staff_today_summary() to authenticated;

create or replace function public.staff_recent_redemptions(p_limit integer default 20)
returns table(redemption_id uuid,voucher_id uuid,voucher_code text,customer_name text,voucher_type text,partner_name text,branch_id uuid,branch_name text,staff_name text,redeem_method text,redemption_status text,redeemed_at timestamptz,notes text)
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_uid uuid := (v_ctx->>'actor_user_id')::uuid;
  v_role text := v_ctx->>'role';
  v_branch_id uuid := nullif(v_ctx->>'branch_id','')::uuid;
begin
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Limit must be between 1 and 100'; end if;
  return query
  select r.id,r.voucher_id,v.voucher_code,v.customer_name,v.voucher_type,p.partner_name,r.branch_id,b.branch_name,r.staff_name_snapshot,r.redeem_method,r.status,r.redeemed_at,r.notes
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  join public.partners p on p.id=r.partner_id
  join public.branches b on b.id=r.branch_id
  where v_role in ('all_branch_manager','admin') or (v_role='manager' and r.branch_id=v_branch_id) or (v_role='staff' and r.staff_user_id=v_uid)
  order by r.redeemed_at desc
  limit p_limit;
end;
$function$;
revoke all on function public.staff_recent_redemptions(integer) from public, anon;
grant execute on function public.staff_recent_redemptions(integer) to authenticated;

create or replace function public.verify_voucher(p_voucher_code text,p_branch_code text default null)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_role text := v_ctx->>'role';
  v_branch_id uuid;
  v_branch_name text;
  v_voucher public.vouchers%rowtype;
  v_allowed boolean:=false;
  v_expired boolean:=false;
  v_display_status text;
begin
  if v_role in ('all_branch_manager','admin') then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where upper(b.branch_code)=upper(trim(p_branch_code)) and b.status='active' limit 1;
  else
    v_branch_id:=nullif(v_ctx->>'branch_id','')::uuid;
    if v_branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where b.id=v_branch_id and b.status='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;
  select * into v_voucher from public.vouchers v where upper(v.voucher_code)=upper(trim(p_voucher_code)) limit 1;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  v_expired:=v_voucher.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date;
  if v_voucher.branch_scope_snapshotted then
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  elsif v_voucher.all_branches then
    v_allowed:=true;
  else
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  end if;
  v_display_status:=case when v_voucher.status='active' and v_expired then 'expired' when v_voucher.status='active' then 'valid' else v_voucher.status end;
  return jsonb_build_object('success',true,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'customer_name',v_voucher.customer_name,'customer_phone',v_voucher.customer_phone,'voucher_type',v_voucher.voucher_type,'expiry_date',v_voucher.expiry_date,'status',v_display_status,'canonical_status',v_voucher.status,'usage_limit',v_voucher.usage_limit,'usage_count',v_voucher.usage_count,'remaining_uses',greatest(0,v_voucher.usage_limit-v_voucher.usage_count),'branch_id',v_branch_id,'branch_name',v_branch_name,'branch_allowed',v_allowed,'expired',v_expired,'can_redeem',v_voucher.status='active' and not v_expired and v_allowed and v_voucher.usage_count<v_voucher.usage_limit,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.verify_voucher(text,text) from public, anon;
grant execute on function public.verify_voucher(text,text) to authenticated;

create or replace function public.redeem_voucher(p_voucher_code text,p_notes text default null,p_branch_code text default null,p_redeem_method text default 'qr')
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_uid uuid := (v_ctx->>'actor_user_id')::uuid;
  v_role text := v_ctx->>'role';
  v_actor_name text := v_ctx->>'staff_name';
  v_voucher public.vouchers%rowtype;
  v_branch_id uuid;
  v_branch_name text;
  v_allowed boolean:=false;
  v_new_usage integer;
  v_now timestamptz:=now();
  v_today date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_redemption_id uuid;
  v_method text;
begin
  v_method:=lower(trim(coalesce(p_redeem_method,'qr')));
  if v_method not in ('qr','manual_code','admin') then return jsonb_build_object('success',false,'error','Invalid redeem method'); end if;
  if v_role in ('all_branch_manager','admin') then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where upper(b.branch_code)=upper(trim(p_branch_code)) and b.status='active' limit 1;
  else
    v_branch_id:=nullif(v_ctx->>'branch_id','')::uuid;
    if v_branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where b.id=v_branch_id and b.status='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;
  select * into v_voucher from public.vouchers v where upper(v.voucher_code)=upper(trim(p_voucher_code)) for update;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  if v_voucher.status='revoked' then return jsonb_build_object('success',false,'error','Voucher has been revoked','status',v_voucher.status); end if;
  if v_voucher.status='expired' or v_voucher.expiry_date<v_today then update public.vouchers set status=case when status='active' then 'expired' else status end,updated_at=v_now where id=v_voucher.id; return jsonb_build_object('success',false,'error','Voucher has expired','status','expired'); end if;
  if v_voucher.status='redeemed' or v_voucher.usage_count>=v_voucher.usage_limit then return jsonb_build_object('success',false,'error','Voucher has already been fully redeemed','status','redeemed'); end if;
  if v_voucher.status<>'active' then return jsonb_build_object('success',false,'error','Voucher is not active','status',v_voucher.status); end if;
  if v_voucher.branch_scope_snapshotted then
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  elsif v_voucher.all_branches then
    v_allowed:=true;
  else
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  end if;
  if not v_allowed then return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch'); end if;
  v_new_usage:=v_voucher.usage_count+1;
  insert into public.redemptions(voucher_id,partner_id,branch_id,staff_user_id,staff_name_snapshot,redeem_method,status,redeemed_at,notes)
  values(v_voucher.id,v_voucher.partner_id,v_branch_id,v_uid,v_actor_name,v_method,'completed',v_now,nullif(trim(coalesce(p_notes,'')),'')) returning id into v_redemption_id;
  update public.vouchers set usage_count=v_new_usage,status=case when v_new_usage>=usage_limit then 'redeemed' else 'active' end,updated_at=v_now where id=v_voucher.id;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,v_actor_name,'voucher_redeemed','redemption',v_redemption_id::text,v_voucher.partner_id,jsonb_build_object('voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'branch_id',v_branch_id,'branch_name',v_branch_name,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit),jsonb_build_object('redeem_method',v_method,'actor_realm',v_ctx->>'actor_realm','branch_scope_source',case when v_voucher.branch_scope_snapshotted then 'voucher_snapshot' else 'legacy' end));
  return jsonb_build_object('success',true,'redemption_id',v_redemption_id,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'customer_name',v_voucher.customer_name,'voucher_type',v_voucher.voucher_type,'branch_id',v_branch_id,'branch_name',v_branch_name,'staff_name',v_actor_name,'redeemed_at',v_now,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit,'remaining_uses',greatest(0,v_voucher.usage_limit-v_new_usage),'status',case when v_new_usage>=v_voucher.usage_limit then 'redeemed' else 'active' end,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.redeem_voucher(text,text,text,text) from public, anon;
grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;

-- Trusted server partner-staff management resolver.
create or replace function public.resolve_partner_management_context(p_actor_user_id uuid,p_partner_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_actor public.partner_users%rowtype;
  v_partner public.partners%rowtype;
  v_admin_name text;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
  if p_actor_user_id is null then raise exception 'Actor user is required'; end if;

  select * into v_actor from public.partner_users pu where pu.user_id=p_actor_user_id and pu.role='partner_admin' and pu.status='active' and pu.removed_at is null limit 1;
  if found then
    if p_partner_id is not null and p_partner_id<>v_actor.partner_id then raise exception 'Partner management context denied'; end if;
    select * into v_partner from public.partners p where p.id=v_actor.partner_id and p.status='active';
    if not found then raise exception 'Active Partner required'; end if;
    return jsonb_build_object('actor_user_id',p_actor_user_id,'actor_realm','partner','actor_name',coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),'partner_id',v_partner.id,'is_admin',false);
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name from public.admin_users a where a.user_id=p_actor_user_id and a.status='active' limit 1;
  if found then
    if p_partner_id is null then raise exception 'Admin must select a Partner'; end if;
    select * into v_partner from public.partners p where p.id=p_partner_id and p.status='active';
    if not found then raise exception 'Active Partner required'; end if;
    return jsonb_build_object('actor_user_id',p_actor_user_id,'actor_realm','admin','actor_name',coalesce(v_admin_name,'Admin'),'partner_id',v_partner.id,'is_admin',true);
  end if;

  raise exception 'Active Partner Admin or Admin actor required';
end;
$function$;
revoke all on function public.resolve_partner_management_context(uuid,uuid) from public, anon, authenticated;
grant execute on function public.resolve_partner_management_context(uuid,uuid) to service_role;

drop function if exists public.partner_provision_staff(uuid,text,text,uuid);
create function public.partner_provision_staff(p_new_user_id uuid,p_staff_name text,p_login_email text,p_actor_user_id uuid,p_partner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_management_context(p_actor_user_id,p_partner_id);
  v_partner public.partners%rowtype;
  v_count integer;
  v_staff public.partner_users%rowtype;
begin
  select * into v_partner from public.partners p where p.id=(v_ctx->>'partner_id')::uuid and p.status='active' for update;
  if not found then raise exception 'Active Partner required'; end if;
  if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then raise exception 'Valid Auth user is required'; end if;
  if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
  if nullif(trim(coalesce(p_login_email,'')),'') is null then raise exception 'Login email is required'; end if;
  select count(*) into v_count from public.partner_users pu where pu.partner_id=v_partner.id and pu.role='partner_staff' and pu.status in ('active','suspended') and pu.removed_at is null;
  if v_count>=v_partner.staff_limit then raise exception 'Staff account limit reached'; end if;
  insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
  values(p_new_user_id,v_partner.id,'partner_staff','active',trim(p_staff_name),lower(trim(p_login_email)))
  returning * into v_staff;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(p_actor_user_id,v_ctx->>'actor_name','partner_staff_created','partner_staff',v_staff.id::text,v_partner.id,jsonb_build_object('staff_name',v_staff.staff_name,'login_email',v_staff.login_email,'status',v_staff.status),jsonb_build_object('provisioning','atomic_rpc','secret_material_logged',false,'actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff',to_jsonb(v_staff),'staff_limit',v_partner.staff_limit,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.partner_provision_staff(uuid,text,text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.partner_provision_staff(uuid,text,text,uuid,uuid) to service_role;

drop function if exists public.partner_update_staff_profile(uuid,text,text,uuid);
create function public.partner_update_staff_profile(p_staff_id uuid,p_action text,p_staff_name text,p_actor_user_id uuid,p_partner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_management_context(p_actor_user_id,p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_target public.partner_users%rowtype;
  v_action text := lower(trim(coalesce(p_action,'')));
  v_now timestamptz := now();
  v_action_type text;
begin
  select * into v_target from public.partner_users pu where pu.id=p_staff_id and pu.partner_id=v_partner_id and pu.role='partner_staff' for update;
  if not found then raise exception 'Partner Staff account not found'; end if;
  if v_action='rename' then
    if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
    update public.partner_users set staff_name=trim(p_staff_name),updated_at=v_now where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_renamed';
  elsif v_action in ('suspend','activate') then
    if v_target.removed_at is not null or v_target.status='removed' then raise exception 'Removed Staff cannot be reactivated'; end if;
    update public.partner_users set status=case when v_action='activate' then 'active' else 'suspended' end,updated_at=v_now where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_status_changed';
  elsif v_action='remove' then
    update public.partner_users set status='removed',removed_at=v_now,updated_at=v_now where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_removed';
  else
    raise exception 'Unsupported Partner Staff action';
  end if;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(p_actor_user_id,v_ctx->>'actor_name',v_action_type,'partner_staff',v_target.id::text,v_partner_id,jsonb_build_object('staff_name',v_target.staff_name,'status',v_target.status,'removed_at',v_target.removed_at),jsonb_build_object('management','atomic_rpc','actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff',to_jsonb(v_target),'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.partner_update_staff_profile(uuid,text,text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.partner_update_staff_profile(uuid,text,text,uuid,uuid) to service_role;

drop function if exists public.partner_record_staff_password_reset(uuid,uuid);
create function public.partner_record_staff_password_reset(p_staff_id uuid,p_actor_user_id uuid,p_partner_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_management_context(p_actor_user_id,p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_target public.partner_users%rowtype;
begin
  select * into v_target from public.partner_users pu where pu.id=p_staff_id and pu.partner_id=v_partner_id and pu.role='partner_staff' and pu.status<>'removed' and pu.removed_at is null;
  if not found then raise exception 'Active Partner Staff target required'; end if;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(p_actor_user_id,v_ctx->>'actor_name','partner_staff_password_reset','partner_staff',v_target.id::text,v_partner_id,jsonb_build_object('staff_name',v_target.staff_name,'login_email',v_target.login_email),jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true,'actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff_id',v_target.id,'user_id',v_target.user_id,'staff_name',v_target.staff_name,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;
revoke all on function public.partner_record_staff_password_reset(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.partner_record_staff_password_reset(uuid,uuid,uuid) to service_role;
