-- Admin management boundaries required by the validated Admin Portal.
-- Replaces direct browser UPDATEs on sensitive Partner data.

drop function if exists public.admin_get_partner_claim_access(uuid);
create function public.admin_get_partner_claim_access(p_partner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_all boolean := false;
  v_codes text[] := '{}'::text[];
  v_names text[] := '{}'::text[];
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id) then
    raise exception 'Partner not found';
  end if;

  select coalesce(s.all_branches,false)
  into v_all
  from public.partner_claim_settings s
  where s.partner_id=p_partner_id;
  if not found then v_all:=false; end if;

  select
    coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]),
    coalesce(array_agg(b.branch_name order by b.branch_name),'{}'::text[])
  into v_codes,v_names
  from public.partner_claim_branches pcb
  join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=p_partner_id
    and b.status='active';

  return jsonb_build_object(
    'success',true,
    'partner_id',p_partner_id,
    'all_branches',v_all,
    'branch_codes',v_codes,
    'branch_names',v_names
  );
end;
$$;
revoke all on function public.admin_get_partner_claim_access(uuid) from public, anon;
grant execute on function public.admin_get_partner_claim_access(uuid) to authenticated;

drop function if exists public.admin_set_partner_status(uuid,text);
create function public.admin_set_partner_status(p_partner_id uuid,p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_status text;
  v_new_status text := lower(trim(coalesce(p_status,'')));
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if v_new_status not in ('active','suspended','archived') then raise exception 'Invalid Partner status'; end if;

  select p.status into v_old_status
  from public.partners p where p.id=p_partner_id for update;
  if not found then raise exception 'Partner not found'; end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.partners
  set status=v_new_status,updated_at=now()
  where id=p_partner_id;

  -- Partner logins follow the Partner status. Historical rows are preserved.
  update public.partner_users
  set status=case
      when v_new_status='active' and removed_at is null then 'active'
      when removed_at is not null then 'removed'
      else 'suspended'
    end,
    updated_at=now()
  where partner_id=p_partner_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data)
  values(v_uid,v_admin_name,'partner_status_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('status',v_old_status),jsonb_build_object('status',v_new_status));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'status',v_new_status);
end;
$$;
revoke all on function public.admin_set_partner_status(uuid,text) from public, anon;
grant execute on function public.admin_set_partner_status(uuid,text) to authenticated;

drop function if exists public.admin_set_partner_voucher_limit(uuid,integer);
create function public.admin_set_partner_voucher_limit(p_partner_id uuid,p_voucher_limit integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_limit integer;
  v_issued integer;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_voucher_limit is null or p_voucher_limit<0 then raise exception 'Voucher limit must be zero or greater'; end if;

  select p.voucher_limit,p.vouchers_issued into v_old_limit,v_issued
  from public.partners p where p.id=p_partner_id for update;
  if not found then raise exception 'Partner not found'; end if;
  if p_voucher_limit<>0 and p_voucher_limit<v_issued then raise exception 'Voucher limit cannot be lower than vouchers already issued'; end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.partners set voucher_limit=p_voucher_limit,updated_at=now() where id=p_partner_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data)
  values(v_uid,v_admin_name,'partner_voucher_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('voucher_limit',v_old_limit),jsonb_build_object('voucher_limit',p_voucher_limit));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'voucher_limit',p_voucher_limit,'vouchers_issued',v_issued);
end;
$$;
revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from public, anon;
grant execute on function public.admin_set_partner_voucher_limit(uuid,integer) to authenticated;

drop function if exists public.admin_set_partner_staff_limit(uuid,integer);
create function public.admin_set_partner_staff_limit(p_partner_id uuid,p_staff_limit integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_limit integer;
  v_active_count integer;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_staff_limit is null or p_staff_limit<0 or p_staff_limit>1000 then raise exception 'Staff limit must be between 0 and 1000'; end if;

  select p.staff_limit into v_old_limit
  from public.partners p where p.id=p_partner_id for update;
  if not found then raise exception 'Partner not found'; end if;

  select count(*) into v_active_count
  from public.partner_users pu
  where pu.partner_id=p_partner_id
    and pu.role='partner_staff'
    and pu.status in ('active','suspended')
    and pu.removed_at is null;

  if p_staff_limit<v_active_count then
    raise exception 'Staff limit cannot be lower than existing non-removed Staff count';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.partners set staff_limit=p_staff_limit,updated_at=now() where id=p_partner_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data)
  values(v_uid,v_admin_name,'partner_staff_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('staff_limit',v_old_limit),jsonb_build_object('staff_limit',p_staff_limit,'existing_staff_count',v_active_count));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'staff_limit',p_staff_limit,'staff_count',v_active_count);
end;
$$;
revoke all on function public.admin_set_partner_staff_limit(uuid,integer) from public, anon;
grant execute on function public.admin_set_partner_staff_limit(uuid,integer) to authenticated;
