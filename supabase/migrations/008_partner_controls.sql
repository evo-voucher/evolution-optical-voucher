-- Partner control RPCs reconstructed from proven legacy behavior.
-- Direct table writes remain blocked; these are explicit mutation boundaries.

drop function if exists public.get_my_partner_dashboard();
create function public.get_my_partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,
    'partner_code',p.partner_code,
    'partner_name',p.partner_name,
    'voucher_limit',p.voucher_limit,
    'vouchers_issued',p.vouchers_issued,
    'remaining',case when p.voucher_limit>0 then greatest(0,p.voucher_limit-p.vouchers_issued) else null end,
    'partner_status',p.status,
    'role',pu.role,
    'staff_name',pu.staff_name,
    'staff_access_enabled',p.staff_access_enabled,
    'staff_limit',p.staff_limit,
    'can_issue_voucher',case
      when pu.role='partner_admin' then true
      when pu.role='partner_staff' then p.staff_access_enabled
      else false
    end
  ) into v_result
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if v_result is null then
    raise exception 'Active Partner account not found';
  end if;

  return v_result;
end;
$$;
revoke all on function public.get_my_partner_dashboard() from public, anon;
grant execute on function public.get_my_partner_dashboard() to authenticated;

drop function if exists public.get_my_partner_claim_access();
create function public.get_my_partner_claim_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner uuid := public.current_partner_id();
  v_all boolean;
  v_branches jsonb;
begin
  if v_partner is null then
    raise exception 'Active Partner account not found';
  end if;

  select coalesce(s.all_branches,false)
  into v_all
  from public.partner_claim_settings s
  where s.partner_id=v_partner;

  if not found then v_all:=false; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'branch_code',b.branch_code,
    'branch_name',b.branch_name,
    'address',b.address,
    'phone',b.phone
  ) order by b.branch_name),'[]'::jsonb)
  into v_branches
  from public.partner_claim_branches pcb
  join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=v_partner
    and b.status='active';

  return jsonb_build_object('success',true,'all_branches',v_all,'branches',v_branches);
end;
$$;
revoke all on function public.get_my_partner_claim_access() from public, anon;
grant execute on function public.get_my_partner_claim_access() to authenticated;

drop function if exists public.partner_set_staff_access(boolean);
create function public.partner_set_staff_access(enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner uuid;
begin
  select pu.partner_id into v_partner
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if v_partner is null then
    raise exception 'Partner Admin access required';
  end if;

  update public.partners
  set staff_access_enabled=coalesce(enabled,false),updated_at=now()
  where id=v_partner;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,partner_id,after_data)
  values ((select auth.uid()),'partner_staff_access_changed','partner',v_partner::text,v_partner,
    jsonb_build_object('staff_access_enabled',coalesce(enabled,false)));

  return jsonb_build_object('success',true,'partner_id',v_partner,'staff_access_enabled',coalesce(enabled,false));
end;
$$;
revoke all on function public.partner_set_staff_access(boolean) from public, anon;
grant execute on function public.partner_set_staff_access(boolean) to authenticated;

drop function if exists public.admin_set_partner_claim_access(uuid,boolean,text[]);
create function public.admin_set_partner_claim_access(
  p_partner_id uuid,
  p_all_branches boolean,
  p_branch_codes text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_admin_name text;
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id) then
    raise exception 'Partner not found';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a
  where a.user_id=(select auth.uid()) and a.status='active';

  insert into public.partner_claim_settings(partner_id,all_branches,updated_at,updated_by)
  values(p_partner_id,coalesce(p_all_branches,false),now(),(select auth.uid()))
  on conflict(partner_id) do update
  set all_branches=excluded.all_branches,updated_at=excluded.updated_at,updated_by=excluded.updated_by;

  delete from public.partner_claim_branches where partner_id=p_partner_id;

  if not coalesce(p_all_branches,false) then
    insert into public.partner_claim_branches(partner_id,branch_id)
    select p_partner_id,b.id
    from public.branches b
    where b.branch_code=any(coalesce(p_branch_codes,'{}'::text[]))
      and b.status='active'
    on conflict do nothing;

    get diagnostics v_count=row_count;
    if v_count=0 then
      raise exception 'Select at least one active claim branch';
    end if;
  end if;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data)
  values((select auth.uid()),v_admin_name,'partner_claim_access_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('all_branches',coalesce(p_all_branches,false),'branch_codes',coalesce(p_branch_codes,'{}'::text[])));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'all_branches',coalesce(p_all_branches,false),'branch_count',v_count);
end;
$$;
revoke all on function public.admin_set_partner_claim_access(uuid,boolean,text[]) from public, anon;
grant execute on function public.admin_set_partner_claim_access(uuid,boolean,text[]) to authenticated;
