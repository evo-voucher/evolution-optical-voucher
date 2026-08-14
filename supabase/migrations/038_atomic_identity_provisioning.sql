-- Atomic server identity provisioning v1
-- Purpose: keep service_role table DML closed while allowing narrowly scoped
-- trusted Edge Functions to provision operational identities transactionally.

create or replace function public.admin_provision_partner(
  p_partner_code text,
  p_partner_name text,
  p_contact_person text,
  p_contact_phone text,
  p_voucher_limit integer,
  p_staff_limit integer,
  p_new_user_id uuid,
  p_login_email text,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_name text;
  v_partner public.partners%rowtype;
  v_partner_user public.partner_users%rowtype;
begin
  if not public.is_trusted_service_role() then
    raise exception 'Trusted server context required';
  end if;
  if p_actor_user_id is null or not exists (
    select 1 from public.admin_users a
    where a.user_id=p_actor_user_id and a.status='active'
  ) then
    raise exception 'Active Admin actor required';
  end if;
  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
  from public.admin_users a where a.user_id=p_actor_user_id and a.status='active';

  if p_new_user_id is null or not exists (select 1 from auth.users u where u.id=p_new_user_id) then
    raise exception 'Valid Auth user is required';
  end if;
  if nullif(trim(coalesce(p_partner_code,'')),'') is null
     or upper(trim(p_partner_code)) !~ '^[A-Z0-9_-]+$' then
    raise exception 'Invalid partner code';
  end if;
  if nullif(trim(coalesce(p_partner_name,'')),'') is null then
    raise exception 'Partner name is required';
  end if;
  if p_voucher_limit is null or p_voucher_limit<0 or p_staff_limit is null or p_staff_limit<0 then
    raise exception 'Limits must be non-negative';
  end if;
  if nullif(trim(coalesce(p_login_email,'')),'') is null then
    raise exception 'Login email is required';
  end if;

  insert into public.partners(
    partner_code,partner_name,contact_person,contact_phone,
    voucher_limit,vouchers_issued,staff_limit,staff_access_enabled,status
  ) values (
    upper(trim(p_partner_code)),trim(p_partner_name),nullif(trim(coalesce(p_contact_person,'')),''),
    nullif(trim(coalesce(p_contact_phone,'')),''),p_voucher_limit,0,p_staff_limit,false,'active'
  ) returning * into v_partner;

  insert into public.partner_users(
    user_id,partner_id,role,status,staff_name,login_email
  ) values (
    p_new_user_id,v_partner.id,'partner_admin','active',
    coalesce(nullif(trim(coalesce(p_contact_person,'')),''),trim(p_partner_name)),
    lower(trim(p_login_email))
  ) returning * into v_partner_user;

  insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
  values(v_partner.id,false,p_actor_user_id);

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    p_actor_user_id,v_actor_name,'partner_created','partner',v_partner.id::text,v_partner.id,
    jsonb_build_object(
      'partner_code',v_partner.partner_code,
      'partner_name',v_partner.partner_name,
      'voucher_limit',v_partner.voucher_limit,
      'staff_limit',v_partner.staff_limit,
      'status',v_partner.status
    ),
    jsonb_build_object('login_email',lower(trim(p_login_email)),'secret_material_logged',false,'provisioning','atomic_rpc')
  );

  return jsonb_build_object(
    'success',true,
    'partner',to_jsonb(v_partner),
    'partner_user_id',v_partner_user.id,
    'user_id',p_new_user_id
  );
end;
$$;

revoke all on function public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid) to service_role;

-- Kept under the historical name for frontend compatibility. The server RPC
-- accepts an active Voucher Admin, all-branch manager, or branch manager actor,
-- and re-enforces the exact role/branch rules before writing.
create or replace function public.admin_provision_staff(
  p_new_user_id uuid,
  p_staff_name text,
  p_branch_id uuid,
  p_role text,
  p_login_email text,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_name text;
  v_is_admin boolean := false;
  v_manager public.staff_users%rowtype;
  v_requested_role text := lower(trim(coalesce(p_role,'')));
  v_staff public.staff_users%rowtype;
begin
  if not public.is_trusted_service_role() then
    raise exception 'Trusted server context required';
  end if;
  if p_actor_user_id is null then
    raise exception 'Actor user is required';
  end if;

  select exists(
    select 1 from public.admin_users a
    where a.user_id=p_actor_user_id and a.status='active'
  ) into v_is_admin;

  if v_is_admin then
    select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
    from public.admin_users a where a.user_id=p_actor_user_id and a.status='active';
  else
    select * into v_manager
    from public.staff_users su
    where su.user_id=p_actor_user_id
      and su.status='active'
      and su.role in ('manager','all_branch_manager')
    limit 1;
    if not found then
      raise exception 'Active Admin or Manager actor required';
    end if;
    v_actor_name:=v_manager.staff_name;
  end if;

  if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then
    raise exception 'Valid Auth user is required';
  end if;
  if nullif(trim(coalesce(p_staff_name,'')),'') is null then
    raise exception 'Staff name is required';
  end if;
  if v_requested_role not in ('staff','manager') then
    raise exception 'Allowed roles: staff, manager';
  end if;
  if not exists(select 1 from public.branches b where b.id=p_branch_id and b.status='active') then
    raise exception 'Active branch is required';
  end if;

  if not v_is_admin and v_manager.role='manager' then
    if v_requested_role<>'staff' then
      raise exception 'Branch Manager can only create Staff accounts';
    end if;
    if v_manager.branch_id is null or p_branch_id is distinct from v_manager.branch_id then
      raise exception 'Branch Manager can only create Staff at assigned branch';
    end if;
  end if;

  insert into public.staff_users(user_id,branch_id,staff_name,role,status)
  values(p_new_user_id,p_branch_id,trim(p_staff_name),v_requested_role,'active')
  returning * into v_staff;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,after_data,metadata
  ) values (
    p_actor_user_id,v_actor_name,'staff_account_created','staff_users',v_staff.id::text,
    jsonb_build_object('staff_name',v_staff.staff_name,'branch_id',v_staff.branch_id,'role',v_staff.role,'status',v_staff.status),
    jsonb_build_object('login_email',lower(trim(coalesce(p_login_email,''))),'secret_material_logged',false,'provisioning','atomic_rpc')
  );

  return jsonb_build_object('success',true,'staff',to_jsonb(v_staff));
end;
$$;

revoke all on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) from public, anon, authenticated;
grant execute on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) to service_role;

comment on function public.admin_provision_partner(text,text,text,text,integer,integer,uuid,text,uuid) is
'Server-only atomic Partner provisioning after Edge has authenticated an active Admin and created the Auth user. Owns Partner, Partner Admin membership, default claim settings and audit as one transaction.';
comment on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) is
'Server-only atomic Evolution Staff provisioning. Revalidates active Admin/Manager actor and branch/role authority inside the database before writing.';
