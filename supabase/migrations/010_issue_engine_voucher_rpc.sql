-- Voucher Engine issuance RPC.
-- Reconstructed from the proven allocation-based multi-voucher flow, simplified to one canonical validity model.

drop function if exists public.issue_engine_voucher(uuid,text,text);
create function public.issue_engine_voucher(
  p_version_id uuid,
  p_customer_name text,
  p_customer_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner_id uuid;
  v_partner_role text;
  v_staff_name text;
  v_staff_access_enabled boolean;
  v_partner_status text;
  v_template public.voucher_templates%rowtype;
  v_version public.voucher_versions%rowtype;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_issued integer := 0;
  v_issue_date date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_expiry_date date;
  v_partner_all_branches boolean := false;
  v_final_all_branches boolean := false;
  v_voucher_id uuid;
  v_voucher_code text;
  v_public_token uuid;
  v_voucher_type text;
  v_branch_count integer := 0;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Customer name is required'; end if;

  select pu.partner_id,pu.role,pu.staff_name,p.staff_access_enabled,p.status
  into v_partner_id,v_partner_role,v_staff_name,v_staff_access_enabled,v_partner_status
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and pu.status='active'
    and pu.removed_at is null
    and pu.role in ('partner_admin','partner_staff')
  limit 1;

  if v_partner_id is null or v_partner_status<>'active' then raise exception 'Active Partner account not found'; end if;
  if v_partner_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;

  select * into v_version
  from public.voucher_versions vv
  where vv.id=p_version_id and vv.status='active'
  limit 1;
  if not found then raise exception 'Active voucher version not found'; end if;

  select * into v_template
  from public.voucher_templates vt
  where vt.id=v_version.template_id and vt.status='active'
  limit 1;
  if not found then raise exception 'Active voucher template not found'; end if;

  if not exists (
    select 1 from public.partner_voucher_access pva
    where pva.partner_id=v_partner_id
      and pva.template_id=v_template.id
      and pva.status='active'
      and (pva.valid_from is null or pva.valid_from<=now())
      and (pva.valid_until is null or pva.valid_until>=now())
  ) then
    raise exception 'This Partner is not authorised for this voucher type';
  end if;

  select * into v_allocation
  from public.partner_voucher_allocations pva
  where pva.partner_id=v_partner_id
    and pva.version_id=p_version_id
    and pva.status='active'
    and (pva.valid_from is null or pva.valid_from<=now())
    and (pva.valid_until is null or pva.valid_until>=now())
  order by pva.created_at desc
  limit 1
  for update;

  if not found then raise exception 'No active allocation is available for this voucher type'; end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.allocation_id=v_allocation.id;

  if v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued<=0 then
    raise exception 'Voucher allocation limit reached';
  end if;

  if v_version.supply_limit is not null then
    if (select count(*) from public.vouchers v where v.version_id=v_version.id) >= v_version.supply_limit then
      raise exception 'Voucher version supply limit reached';
    end if;
  end if;

  case v_version.validity_mode
    when 'fixed' then
      if v_version.valid_from is not null and v_issue_date<v_version.valid_from then raise exception 'Voucher campaign has not started'; end if;
      if v_version.valid_until is null or v_issue_date>v_version.valid_until then raise exception 'Voucher campaign has ended'; end if;
      v_expiry_date:=v_version.valid_until;
    when 'days' then
      v_expiry_date:=v_issue_date+v_version.valid_days;
    when 'months' then
      v_expiry_date:=(v_issue_date + make_interval(months=>v_version.valid_months))::date;
    else
      raise exception 'Voucher validity is not configured';
  end case;

  select coalesce(s.all_branches,false) into v_partner_all_branches
  from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=false; end if;

  v_final_all_branches:=v_partner_all_branches and v_version.all_branches;

  if not v_final_all_branches then
    if not v_partner_all_branches and v_version.all_branches then
      select count(*) into v_branch_count
      from public.partner_claim_branches pcb
      join public.branches b on b.id=pcb.branch_id
      where pcb.partner_id=v_partner_id and b.status='active';
    elsif v_partner_all_branches and not v_version.all_branches then
      select count(*) into v_branch_count
      from public.voucher_version_branches vvb
      join public.branches b on b.id=vvb.branch_id
      where vvb.version_id=v_version.id and b.status='active';
    else
      select count(*) into v_branch_count
      from public.partner_claim_branches pcb
      join public.voucher_version_branches vvb on vvb.branch_id=pcb.branch_id
      join public.branches b on b.id=pcb.branch_id
      where pcb.partner_id=v_partner_id and vvb.version_id=v_version.id and b.status='active';
    end if;

    if v_branch_count=0 then raise exception 'No valid redemption branch is shared by Partner and Voucher Version'; end if;
  end if;

  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case
    when v_version.face_value is not null then 'RM'||trim(to_char(v_version.face_value,'FM999999990.##'))||' '||v_template.template_name
    when v_version.discount_percent is not null then trim(to_char(v_version.discount_percent,'FM999999990.##'))||'% '||v_template.template_name
    else v_template.template_name
  end;

  insert into public.vouchers(
    voucher_code,partner_id,customer_name,customer_phone,voucher_type,status,expiry_date,
    issued_by_user_id,issued_by_name,all_branches,usage_limit,usage_count,
    template_id,version_id,allocation_id,metadata
  ) values (
    v_voucher_code,v_partner_id,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,'active',v_expiry_date,
    v_uid,coalesce(nullif(trim(coalesce(v_staff_name,'')),''),case when v_partner_role='partner_admin' then 'Partner Admin' else 'Partner Staff' end),
    v_final_all_branches,v_version.usage_limit,0,
    v_template.id,v_version.id,v_allocation.id,
    jsonb_build_object(
      'issuance_path','engine_v1',
      'template_code',v_template.template_code,
      'version_no',v_version.version_no,
      'theme_code',coalesce(v_version.theme_override_code,v_template.theme_code)
    )
  ) returning id,public_token into v_voucher_id,v_public_token;

  if not v_final_all_branches then
    if not v_partner_all_branches and v_version.all_branches then
      insert into public.voucher_branches(voucher_id,branch_id)
      select v_voucher_id,pcb.branch_id
      from public.partner_claim_branches pcb
      join public.branches b on b.id=pcb.branch_id
      where pcb.partner_id=v_partner_id and b.status='active';
    elsif v_partner_all_branches and not v_version.all_branches then
      insert into public.voucher_branches(voucher_id,branch_id)
      select v_voucher_id,vvb.branch_id
      from public.voucher_version_branches vvb
      join public.branches b on b.id=vvb.branch_id
      where vvb.version_id=v_version.id and b.status='active';
    else
      insert into public.voucher_branches(voucher_id,branch_id)
      select v_voucher_id,pcb.branch_id
      from public.partner_claim_branches pcb
      join public.voucher_version_branches vvb on vvb.branch_id=pcb.branch_id
      join public.branches b on b.id=pcb.branch_id
      where pcb.partner_id=v_partner_id and vvb.version_id=v_version.id and b.status='active';
    end if;
  end if;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,coalesce(v_staff_name,v_partner_role),'engine_voucher_issued','voucher',v_voucher_id::text,v_partner_id,
    jsonb_build_object('voucher_code',v_voucher_code,'template_code',v_template.template_code,'version_no',v_version.version_no,'expiry_date',v_expiry_date),
    jsonb_build_object('allocation_id',v_allocation.id,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1)));

  return jsonb_build_object(
    'success',true,
    'voucher_id',v_voucher_id,
    'voucher_code',v_voucher_code,
    'public_token',v_public_token,
    'partner_id',v_partner_id,
    'template_id',v_template.id,
    'template_code',v_template.template_code,
    'template_name',v_template.template_name,
    'version_id',v_version.id,
    'version_no',v_version.version_no,
    'version_name',v_version.version_name,
    'voucher_type',v_voucher_type,
    'expiry_date',v_expiry_date,
    'all_branches',v_final_all_branches,
    'usage_limit',v_version.usage_limit,
    'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),
    'theme_code',coalesce(v_version.theme_override_code,v_template.theme_code),
    'theme_config',case when v_version.theme_override_code is not null then v_version.theme_override_config else v_template.theme_config end
  );
end;
$$;

revoke all on function public.issue_engine_voucher(uuid,text,text) from public, anon;
grant execute on function public.issue_engine_voucher(uuid,text,text) to authenticated;
