-- Converge Staff / Partner Portal RPCs with the current hardened production shape.
-- Production is the read-only reference. This migration targets fresh rebuild / Stage parity.

create or replace function public.resolve_partner_management_context(p_actor_user_id uuid, p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_actor public.partner_users%rowtype;
  v_partner public.partners%rowtype;
  v_admin_name text;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
  if p_actor_user_id is null then raise exception 'Actor user is required'; end if;

  select * into v_actor
  from public.partner_users pu
  where pu.user_id=p_actor_user_id
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
  limit 1;

  if found then
    if p_partner_id is not null and p_partner_id<>v_actor.partner_id then
      raise exception 'Partner management context denied';
    end if;
    select * into v_partner from public.partners p where p.id=v_actor.partner_id and p.status='active';
    if not found then raise exception 'Active Partner required'; end if;
    return jsonb_build_object(
      'actor_user_id',p_actor_user_id,
      'actor_realm','partner',
      'actor_name',coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),
      'partner_id',v_partner.id,
      'is_admin',false
    );
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a
  where a.user_id=p_actor_user_id and a.status='active'
  limit 1;
  if found then
    if p_partner_id is null then raise exception 'Admin must select a Partner'; end if;
    select * into v_partner from public.partners p where p.id=p_partner_id and p.status='active';
    if not found then raise exception 'Active Partner required'; end if;
    return jsonb_build_object(
      'actor_user_id',p_actor_user_id,
      'actor_realm','admin',
      'actor_name',coalesce(v_admin_name,'Admin'),
      'partner_id',v_partner.id,
      'is_admin',true
    );
  end if;

  raise exception 'Active Partner Admin or Admin actor required';
end;
$function$;

create or replace function public.resolve_partner_portal_context(p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
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

create or replace function public.resolve_staff_portal_context()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_admin_name text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid and su.status='active'
  limit 1;

  if found then
    return jsonb_build_object(
      'actor_user_id',v_uid,
      'actor_realm','staff',
      'staff_name',v_staff.staff_name,
      'role',v_staff.role,
      'branch_id',v_staff.branch_id,
      'is_admin',false
    );
  end if;

  if public.is_voucher_admin() then
    select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
    from public.admin_users a
    where a.user_id=v_uid and a.status='active'
    limit 1;
    return jsonb_build_object(
      'actor_user_id',v_uid,
      'actor_realm','admin',
      'staff_name',coalesce(v_admin_name,'Admin'),
      'role','admin',
      'branch_id',null,
      'is_admin',true
    );
  end if;

  raise exception 'Active Staff or Admin account required';
end;
$function$;

create or replace function public.admin_provision_staff(p_new_user_id uuid, p_staff_name text, p_branch_id uuid, p_role text, p_login_email text, p_actor_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_name text;
  v_is_admin boolean := false;
  v_manager public.staff_users%rowtype;
  v_requested_role text := lower(trim(coalesce(p_role,'')));
  v_staff public.staff_users%rowtype;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
  if p_actor_user_id is null then raise exception 'Actor user is required'; end if;

  select exists(select 1 from public.admin_users a where a.user_id=p_actor_user_id and a.status='active') into v_is_admin;
  if v_is_admin then
    select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
    from public.admin_users a where a.user_id=p_actor_user_id and a.status='active';
  else
    select * into v_manager
    from public.staff_users su
    where su.user_id=p_actor_user_id and su.status='active' and su.role in ('manager','all_branch_manager')
    limit 1;
    if not found then raise exception 'Active Admin or Manager actor required'; end if;
    v_actor_name:=v_manager.staff_name;
  end if;

  if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then raise exception 'Valid Auth user is required'; end if;
  if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
  if v_requested_role not in ('staff','manager') then raise exception 'Allowed roles: staff, manager'; end if;
  if not exists(select 1 from public.branches b where b.id=p_branch_id and b.status='active') then raise exception 'Active branch is required'; end if;

  if v_requested_role='manager' and exists(
    select 1 from public.staff_users su
    where su.status='active' and su.role='manager' and su.branch_id=p_branch_id
  ) then
    raise exception 'Only one active Branch Manager is allowed for this branch. Suspend or change the current Branch Manager before assigning another.';
  end if;

  if not v_is_admin and v_manager.role='manager' then
    if v_requested_role<>'staff' then raise exception 'Branch Manager can only create Staff accounts'; end if;
    if v_manager.branch_id is null or p_branch_id is distinct from v_manager.branch_id then raise exception 'Branch Manager can only create Staff at assigned branch'; end if;
  end if;

  insert into public.staff_users(user_id,branch_id,staff_name,login_email,role,status)
  values(p_new_user_id,p_branch_id,trim(p_staff_name),lower(trim(coalesce(p_login_email,''))),v_requested_role,'active')
  returning * into v_staff;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,after_data,metadata)
  values(
    p_actor_user_id,v_actor_name,'staff_account_created','staff_users',v_staff.id::text,
    jsonb_build_object('staff_name',v_staff.staff_name,'branch_id',v_staff.branch_id,'role',v_staff.role,'status',v_staff.status),
    jsonb_build_object('login_email',lower(trim(coalesce(p_login_email,''))),'secret_material_logged',false,'provisioning','atomic_rpc')
  );

  return jsonb_build_object('success',true,'staff',to_jsonb(v_staff));
end;
$function$;

create or replace function public.admin_record_staff_password_reset(p_staff_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_target public.staff_users%rowtype;
begin
  if v_uid is null or not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  select * into v_target from public.staff_users where id=p_staff_id;
  if not found then raise exception 'Evolution Staff account not found'; end if;
  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active' limit 1;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,after_data,metadata)
  values(v_uid,v_admin_name,'evolution_staff_password_reset','staff_users',v_target.id::text,
    jsonb_build_object('staff_name',v_target.staff_name,'login_email',v_target.login_email),
    jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true));
  return jsonb_build_object('success',true,'staff_id',v_target.id,'user_id',v_target.user_id,'staff_name',v_target.staff_name);
end;
$function$;

create or replace function public.admin_staff_directory()
returns table(staff_id uuid, user_id uuid, staff_name text, login_email text, staff_role text, staff_status text, branch_id uuid, branch_code text, branch_name text, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query
  select su.id,su.user_id,su.staff_name,su.login_email,su.role,su.status,
         su.branch_id,b.branch_code,b.branch_name,su.created_at,su.updated_at
  from public.staff_users su
  left join public.branches b on b.id=su.branch_id
  order by case when su.status='active' then 0 else 1 end, lower(su.staff_name), su.created_at;
end;
$function$;

create or replace function public.admin_update_staff_profile(p_staff_id uuid, p_staff_name text default null::text, p_branch_id uuid default null::uuid, p_role text default null::text, p_status text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_target public.staff_users%rowtype;
  v_new_role text;
  v_new_status text;
  v_new_branch_id uuid;
begin
  if v_uid is null or not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select * into v_target from public.staff_users where id=p_staff_id for update;
  if not found then raise exception 'Evolution Staff account not found'; end if;

  v_new_role := lower(trim(coalesce(p_role,v_target.role)));
  v_new_status := lower(trim(coalesce(p_status,v_target.status)));
  v_new_branch_id := case when v_new_role='all_branch_manager' then null else coalesce(p_branch_id,v_target.branch_id) end;

  if v_new_role not in ('staff','manager','all_branch_manager') then raise exception 'Invalid Staff role'; end if;
  if v_new_status not in ('active','suspended','removed') then raise exception 'Invalid Staff status'; end if;

  if v_target.role in ('manager','all_branch_manager') and v_target.status='active' and v_new_status in ('suspended','removed') and not public.is_voucher_admin() then
    raise exception 'Only Admin may suspend or revoke the active Manager';
  end if;

  if v_new_role <> 'all_branch_manager' then
    if v_new_branch_id is null then raise exception 'Branch is required'; end if;
    if not exists(select 1 from public.branches b where b.id=v_new_branch_id and b.status='active') then raise exception 'Active branch is required'; end if;
  end if;

  if v_new_status='active' and v_new_role='manager' and exists(
    select 1 from public.staff_users su where su.id<>p_staff_id and su.status='active' and su.role='manager' and su.branch_id=v_new_branch_id
  ) then
    raise exception 'Only one active Branch Manager is allowed for this branch. Suspend or change the current Branch Manager before assigning another.';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active' limit 1;

  update public.staff_users
  set staff_name=coalesce(nullif(trim(p_staff_name),''),staff_name),
      branch_id=v_new_branch_id,
      role=v_new_role,
      status=v_new_status,
      updated_at=now()
  where id=p_staff_id
  returning * into v_target;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,after_data)
  values(
    v_uid,v_admin_name,
    case
      when v_new_status='suspended' and v_new_role in ('manager','all_branch_manager') then 'evolution_manager_suspended'
      when v_new_status='removed' and v_new_role in ('manager','all_branch_manager') then 'evolution_manager_revoked'
      else 'evolution_staff_updated'
    end,
    'staff_users',v_target.id::text,
    jsonb_build_object('staff_name',v_target.staff_name,'branch_id',v_target.branch_id,'role',v_target.role,'status',v_target.status)
  );

  return jsonb_build_object('success',true,'staff',to_jsonb(v_target));
end;
$function$;

create or replace function public.partner_provision_staff(p_new_user_id uuid, p_staff_name text, p_login_email text, p_actor_user_id uuid, p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
  values(p_actor_user_id,v_ctx->>'actor_name','partner_staff_created','partner_staff',v_staff.id::text,v_partner.id,
    jsonb_build_object('staff_name',v_staff.staff_name,'login_email',v_staff.login_email,'status',v_staff.status),
    jsonb_build_object('provisioning','atomic_rpc','secret_material_logged',false,'actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff',to_jsonb(v_staff),'staff_limit',v_partner.staff_limit,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;

create or replace function public.partner_record_staff_password_reset(p_staff_id uuid, p_actor_user_id uuid, p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ctx jsonb := public.resolve_partner_management_context(p_actor_user_id,p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_target public.partner_users%rowtype;
begin
  select * into v_target from public.partner_users pu
  where pu.id=p_staff_id and pu.partner_id=v_partner_id and pu.role='partner_staff' and pu.status<>'removed' and pu.removed_at is null;
  if not found then raise exception 'Active Partner Staff target required'; end if;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(p_actor_user_id,v_ctx->>'actor_name','partner_staff_password_reset','partner_staff',v_target.id::text,v_partner_id,
    jsonb_build_object('staff_name',v_target.staff_name,'login_email',v_target.login_email),
    jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true,'actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff_id',v_target.id,'user_id',v_target.user_id,'staff_name',v_target.staff_name,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;

create or replace function public.partner_staff_directory(p_partner_id uuid default null::uuid)
returns table(staff_id uuid, user_id uuid, staff_name text, login_email text, staff_status text, created_at timestamp with time zone, updated_at timestamp with time zone, removed_at timestamp with time zone)
language plpgsql
security definer
set search_path to 'public'
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

create or replace function public.partner_update_staff_profile(p_staff_id uuid, p_action text, p_staff_name text, p_actor_user_id uuid, p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
  values(p_actor_user_id,v_ctx->>'actor_name',v_action_type,'partner_staff',v_target.id::text,v_partner_id,
    jsonb_build_object('staff_name',v_target.staff_name,'status',v_target.status,'removed_at',v_target.removed_at),
    jsonb_build_object('management','atomic_rpc','actor_realm',v_ctx->>'actor_realm'));
  return jsonb_build_object('success',true,'staff',to_jsonb(v_target),'actor_realm',v_ctx->>'actor_realm');
end;
$function$;

create or replace function public.staff_operational_context()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
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
    into v_branches
    from public.branches b
    where b.status='active';
  else
    if v_branch_id is null then raise exception 'Staff account has no branch assigned'; end if;
    select * into v_branch from public.branches b where b.id=v_branch_id and b.status='active';
    if not found then raise exception 'Assigned branch is not active'; end if;
    v_branches:=jsonb_build_array(jsonb_build_object('branch_id',v_branch.id,'branch_code',v_branch.branch_code,'branch_name',v_branch.branch_name,'address',v_branch.address,'phone',v_branch.phone));
  end if;
  return jsonb_build_object(
    'success',true,
    'staff_user_id',(v_ctx->>'actor_user_id')::uuid,
    'staff_name',v_ctx->>'staff_name',
    'role',v_role,
    'branch_id',v_branch_id,
    'branch_selection_required',v_role in ('all_branch_manager','admin'),
    'branches',v_branches,
    'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false)
  );
end;
$function$;

create or replace function public.staff_recent_redemptions(p_limit integer default 20)
returns table(redemption_id uuid, voucher_id uuid, voucher_code text, customer_name text, voucher_type text, partner_name text, branch_id uuid, branch_name text, staff_name text, redeem_method text, redemption_status text, redeemed_at timestamp with time zone, notes text)
language plpgsql
stable security definer
set search_path to 'public'
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
  where
    v_role in ('all_branch_manager','admin')
    or (v_role='manager' and r.branch_id=v_branch_id)
    or (v_role='staff' and r.staff_user_id=v_uid)
  order by r.redeemed_at desc
  limit p_limit;
end;
$function$;

create or replace function public.staff_today_summary()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
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
    and (
      v_role in ('all_branch_manager','admin')
      or (v_role='manager' and r.branch_id=v_branch_id)
      or (v_role='staff' and r.staff_user_id=v_uid)
    );
  return jsonb_build_object(
    'success',true,
    'staff_user_id',v_uid,
    'staff_name',v_ctx->>'staff_name',
    'role',v_role,
    'branch_id',v_branch_id,
    'today_redeemed',v_count,
    'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false)
  );
end;
$function$;

-- Retire legacy Partner Staff signatures left by the hosted compatibility layer.
drop function if exists public.partner_provision_staff(uuid,text,text,uuid);
drop function if exists public.partner_record_staff_password_reset(uuid,uuid);
drop function if exists public.partner_staff_directory();
drop function if exists public.partner_update_staff_profile(uuid,text,text,uuid);

-- Align execute privileges with current production.
revoke all on function public.resolve_partner_management_context(uuid,uuid) from public, anon, authenticated;
grant execute on function public.resolve_partner_management_context(uuid,uuid) to service_role;

revoke all on function public.resolve_partner_portal_context(uuid) from public, anon, authenticated, service_role;
grant execute on function public.resolve_partner_portal_context(uuid) to authenticated;

revoke all on function public.resolve_staff_portal_context() from public, anon, authenticated, service_role;
grant execute on function public.resolve_staff_portal_context() to authenticated;

revoke all on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) from public, anon, authenticated, service_role;
grant execute on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) to service_role;

revoke all on function public.admin_record_staff_password_reset(uuid) from public, anon, authenticated, service_role;
grant execute on function public.admin_record_staff_password_reset(uuid) to authenticated, service_role;

revoke all on function public.admin_staff_directory() from public, anon, authenticated, service_role;
grant execute on function public.admin_staff_directory() to authenticated, service_role;

revoke all on function public.admin_update_staff_profile(uuid,text,uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_staff_profile(uuid,text,uuid,text,text) to authenticated, service_role;

revoke all on function public.partner_provision_staff(uuid,text,text,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_provision_staff(uuid,text,text,uuid,uuid) to service_role;

revoke all on function public.partner_record_staff_password_reset(uuid,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_record_staff_password_reset(uuid,uuid,uuid) to service_role;

revoke all on function public.partner_staff_directory(uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_staff_directory(uuid) to authenticated;

revoke all on function public.partner_update_staff_profile(uuid,text,text,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_update_staff_profile(uuid,text,text,uuid,uuid) to service_role;

revoke all on function public.staff_operational_context() from public, anon, authenticated, service_role;
grant execute on function public.staff_operational_context() to authenticated;

revoke all on function public.staff_recent_redemptions(integer) from public, anon, authenticated, service_role;
grant execute on function public.staff_recent_redemptions(integer) to authenticated;

revoke all on function public.staff_today_summary() from public, anon, authenticated, service_role;
grant execute on function public.staff_today_summary() to authenticated;
