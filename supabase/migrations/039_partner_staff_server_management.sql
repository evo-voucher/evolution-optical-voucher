-- Partner Staff server management v1
-- Partner Admin caller identity is revalidated inside each service_role-only RPC.
-- Partner identity is always derived from that actor; no caller-supplied Partner id.

create or replace function public.partner_provision_staff(
  p_new_user_id uuid,
  p_staff_name text,
  p_login_email text,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.partner_users%rowtype;
  v_partner public.partners%rowtype;
  v_count integer;
  v_staff public.partner_users%rowtype;
begin
  if not public.is_trusted_service_role() then
    raise exception 'Trusted server context required';
  end if;

  select * into v_actor
  from public.partner_users pu
  where pu.user_id=p_actor_user_id
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
  limit 1;
  if not found then raise exception 'Active Partner Admin actor required'; end if;

  select * into v_partner
  from public.partners p
  where p.id=v_actor.partner_id and p.status='active'
  for update;
  if not found then raise exception 'Active Partner required'; end if;

  if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then
    raise exception 'Valid Auth user is required';
  end if;
  if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
  if nullif(trim(coalesce(p_login_email,'')),'') is null then raise exception 'Login email is required'; end if;

  select count(*) into v_count
  from public.partner_users pu
  where pu.partner_id=v_partner.id
    and pu.role='partner_staff'
    and pu.status in ('active','suspended')
    and pu.removed_at is null;

  if v_count>=v_partner.staff_limit then
    raise exception 'Staff account limit reached';
  end if;

  insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
  values(p_new_user_id,v_partner.id,'partner_staff','active',trim(p_staff_name),lower(trim(p_login_email)))
  returning * into v_staff;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    p_actor_user_id,coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),
    'partner_staff_created','partner_staff',v_staff.id::text,v_partner.id,
    jsonb_build_object('staff_name',v_staff.staff_name,'login_email',v_staff.login_email,'status',v_staff.status),
    jsonb_build_object('provisioning','atomic_rpc','secret_material_logged',false)
  );

  return jsonb_build_object('success',true,'staff',to_jsonb(v_staff),'staff_limit',v_partner.staff_limit);
end;
$$;
revoke all on function public.partner_provision_staff(uuid,text,text,uuid) from public, anon, authenticated;
grant execute on function public.partner_provision_staff(uuid,text,text,uuid) to service_role;

create or replace function public.partner_update_staff_profile(
  p_staff_id uuid,
  p_action text,
  p_staff_name text,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.partner_users%rowtype;
  v_partner public.partners%rowtype;
  v_target public.partner_users%rowtype;
  v_action text := lower(trim(coalesce(p_action,'')));
  v_now timestamptz := now();
  v_action_type text;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;

  select * into v_actor
  from public.partner_users pu
  where pu.user_id=p_actor_user_id
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
  limit 1;
  if not found then raise exception 'Active Partner Admin actor required'; end if;

  select * into v_partner from public.partners p
  where p.id=v_actor.partner_id and p.status='active';
  if not found then raise exception 'Active Partner required'; end if;

  select * into v_target
  from public.partner_users pu
  where pu.id=p_staff_id
    and pu.partner_id=v_partner.id
    and pu.role='partner_staff'
  for update;
  if not found then raise exception 'Partner Staff account not found'; end if;

  if v_action='rename' then
    if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
    update public.partner_users set staff_name=trim(p_staff_name),updated_at=v_now
    where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_renamed';
  elsif v_action in ('suspend','activate') then
    if v_target.removed_at is not null or v_target.status='removed' then
      raise exception 'Removed Staff cannot be reactivated';
    end if;
    update public.partner_users
    set status=case when v_action='activate' then 'active' else 'suspended' end,updated_at=v_now
    where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_status_changed';
  elsif v_action='remove' then
    update public.partner_users set status='removed',removed_at=v_now,updated_at=v_now
    where id=v_target.id returning * into v_target;
    v_action_type:='partner_staff_removed';
  else
    raise exception 'Unsupported Partner Staff action';
  end if;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    p_actor_user_id,coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),v_action_type,
    'partner_staff',v_target.id::text,v_partner.id,
    jsonb_build_object('staff_name',v_target.staff_name,'status',v_target.status,'removed_at',v_target.removed_at),
    jsonb_build_object('management','atomic_rpc')
  );

  return jsonb_build_object('success',true,'staff',to_jsonb(v_target));
end;
$$;
revoke all on function public.partner_update_staff_profile(uuid,text,text,uuid) from public, anon, authenticated;
grant execute on function public.partner_update_staff_profile(uuid,text,text,uuid) to service_role;

create or replace function public.partner_record_staff_password_reset(
  p_staff_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.partner_users%rowtype;
  v_target public.partner_users%rowtype;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;

  select * into v_actor from public.partner_users pu
  where pu.user_id=p_actor_user_id and pu.role='partner_admin' and pu.status='active' and pu.removed_at is null
  limit 1;
  if not found then raise exception 'Active Partner Admin actor required'; end if;

  select * into v_target from public.partner_users pu
  where pu.id=p_staff_id and pu.partner_id=v_actor.partner_id and pu.role='partner_staff'
    and pu.status<>'removed' and pu.removed_at is null;
  if not found then raise exception 'Active Partner Staff target required'; end if;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    p_actor_user_id,coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),'partner_staff_password_reset',
    'partner_staff',v_target.id::text,v_actor.partner_id,
    jsonb_build_object('staff_name',v_target.staff_name,'login_email',v_target.login_email),
    jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true)
  );

  return jsonb_build_object('success',true,'staff_id',v_target.id,'user_id',v_target.user_id,'staff_name',v_target.staff_name);
end;
$$;
revoke all on function public.partner_record_staff_password_reset(uuid,uuid) from public, anon, authenticated;
grant execute on function public.partner_record_staff_password_reset(uuid,uuid) to service_role;

comment on function public.partner_provision_staff(uuid,text,text,uuid) is
'Server-only Partner Staff provisioning. Derives Partner from active Partner Admin actor and locks Partner row before enforcing staff_limit.';
comment on function public.partner_update_staff_profile(uuid,text,text,uuid) is
'Server-only Partner Staff rename/status/remove mutation scoped to the actor Partner.';
comment on function public.partner_record_staff_password_reset(uuid,uuid) is
'Server-only audit boundary for successful Partner Staff password reset; validates actor and target tenant.';
