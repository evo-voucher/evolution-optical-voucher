-- Admin Superuser Partner Catalog + Issue Compatibility
-- Production-applied: 2026-08-16
-- Admin uses only the internal ADMIN system Partner context; normal Partner tenant isolation is unchanged.

create or replace function public.partner_issuable_voucher_catalog()
returns table(version_id uuid, template_id uuid, template_code text, template_name text, version_no integer, version_name text, voucher_label text, face_value numeric, discount_percent numeric, validity_mode text, valid_days integer, valid_months integer, valid_until date, usage_limit integer, transferable boolean, terms_text text, remaining_allocation bigint, remaining_supply bigint)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_partner_id uuid; v_role text; v_staff_access_enabled boolean; v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select pu.partner_id,lower(coalesce(pu.role,'')),coalesce(p.staff_access_enabled,false)
  into v_partner_id,v_role,v_staff_access_enabled
  from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid()) and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff') and lower(coalesce(p.status,''))='active'
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end limit 1;
  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
  if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;

  return query select vv.id,vt.id,vt.template_code,vt.template_name,vv.version_no,vv.version_name,
    case when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))||' '||vt.template_name
         when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'% '||vt.template_name
         else vt.template_name end,
    vv.face_value,vv.discount_percent,
    coalesce(vv.validity_mode,case lower(coalesce(vv.validity_type,'')) when 'fixed' then 'fixed' else 'days' end),
    vv.valid_days,vv.valid_months,vv.valid_until,coalesce(vv.usage_limit,1),coalesce(vv.transferable,true),vv.terms_text,
    greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0))::bigint,
    case when vv.supply_limit is null then null else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint end
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id and lower(coalesce(vt.status,''))='active'
  join public.partner_voucher_access pva on pva.partner_id=v_partner_id and pva.template_id=vv.template_id and lower(coalesce(pva.status,''))='active'
    and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())
  join lateral (
    select pa.id,pa.quantity_allocated,pa.quantity_revoked
    from public.partner_voucher_allocations pa
    where pa.partner_id=v_partner_id and pa.version_id=vv.id and lower(coalesce(pa.status,''))='active'
      and (pa.valid_from is null or pa.valid_from<=now()) and (pa.valid_until is null or pa.valid_until>=now())
    order by pa.created_at desc limit 1
  ) a on true
  left join lateral (select count(*)::bigint as issued_count from public.vouchers v where v.allocation_id=a.id) ai on true
  left join lateral (select count(*)::bigint as issued_count from public.vouchers v where v.version_id=vv.id) vi on true
  where lower(coalesce(vv.status,''))='active'
    and (coalesce(vv.validity_mode,case lower(coalesce(vv.validity_type,'')) when 'fixed' then 'fixed' else 'days' end)<>'fixed'
         or (vv.valid_until is not null and vv.valid_until>=v_today and (vv.valid_from is null or vv.valid_from<=v_today)))
    and (a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0)>0
    and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
  order by vt.template_name,vv.version_no desc;
end;$function$;

create or replace function public.create_partner_multi_voucher_controlled(p_version_id uuid, p_customer_name text, p_customer_phone text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_partner_id uuid; v_role text; v_staff_name text; v_staff_access_enabled boolean; v_partner_status text;
  v_template_id uuid; v_template_code text; v_template_name text; v_category text; v_version_no integer; v_version_name text;
  v_face_value numeric; v_discount_percent numeric; v_validity_type text; v_valid_days integer; v_valid_from date; v_valid_until date; v_version_all_branches boolean;
  v_allocation_id uuid; v_allocated integer; v_revoked integer; v_issued integer; v_partner_all_branches boolean; v_branch_codes text[];
  v_voucher_id uuid; v_voucher_code text; v_public_token uuid; v_activated_at timestamptz:=now(); v_issue_date date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_expiry_date date; v_voucher_type text; v_actor_name text;
begin
  if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Customer name is required'; end if;

  select pu.partner_id,lower(coalesce(pu.role,'')),pu.staff_name,coalesce(p.staff_access_enabled,false),lower(coalesce(p.status,''))
  into v_partner_id,v_role,v_staff_name,v_staff_access_enabled,v_partner_status
  from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=auth.uid() and lower(coalesce(pu.status,''))='active' and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff')
  order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end limit 1;

  if v_partner_id is null or v_partner_status<>'active' then raise exception 'Active Partner account not found'; end if;
  if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is currently disabled by your Partner Admin.'; end if;
  v_actor_name:=case when v_role='admin' then 'Admin' when v_role='partner_staff' then coalesce(nullif(v_staff_name,''),'Partner Staff') else 'Partner Admin' end;

  select vt.id,vt.template_code,vt.template_name,vt.voucher_category,vv.version_no,vv.version_name,vv.face_value,vv.discount_percent,
         vv.validity_type,vv.valid_days,vv.valid_from,vv.valid_until,vv.all_branches
  into v_template_id,v_template_code,v_template_name,v_category,v_version_no,v_version_name,v_face_value,v_discount_percent,
       v_validity_type,v_valid_days,v_valid_from,v_valid_until,v_version_all_branches
  from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active' limit 1;
  if v_template_id is null then raise exception 'Active voucher version not found'; end if;

  if not exists(
    select 1 from public.partner_voucher_access pva
    where pva.partner_id=v_partner_id and pva.template_id=v_template_id and pva.status='active'
      and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())
  ) then raise exception 'This Partner is not authorised for this voucher type'; end if;

  select pva.id,pva.quantity_allocated,pva.quantity_revoked
  into v_allocation_id,v_allocated,v_revoked
  from public.partner_voucher_allocations pva
  where pva.partner_id=v_partner_id and pva.version_id=p_version_id and pva.status='active'
    and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())
  order by pva.created_at desc limit 1 for update;
  if v_allocation_id is null then raise exception 'No active allocation is available for this voucher type'; end if;

  select count(*) into v_issued from public.vouchers where allocation_id=v_allocation_id;
  if coalesce(v_allocated,0)-coalesce(v_revoked,0)-coalesce(v_issued,0)<=0 then raise exception 'Voucher allocation limit reached'; end if;

  if v_validity_type='fixed' then
    if v_valid_from is not null and v_issue_date<v_valid_from then raise exception 'Voucher campaign has not started'; end if;
    if v_valid_until is null or v_issue_date>v_valid_until then raise exception 'Voucher campaign has ended'; end if;
    v_expiry_date:=v_valid_until;
  else
    if coalesce(v_valid_days,0)<=0 then raise exception 'Voucher validity is not configured'; end if;
    v_expiry_date:=v_issue_date+v_valid_days;
  end if;

  select coalesce(s.all_branches,true) into v_partner_all_branches from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=true; end if;

  if v_partner_all_branches and coalesce(v_version_all_branches,false) then
    v_branch_codes:='{}'::text[];
  elsif not v_partner_all_branches and coalesce(v_version_all_branches,false) then
    select coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]) into v_branch_codes
    from public.partner_claim_branches pcb join public.branches b on b.id=pcb.branch_id
    where pcb.partner_id=v_partner_id and lower(coalesce(b.status,'active'))='active';
    if coalesce(array_length(v_branch_codes,1),0)=0 then raise exception 'No claim branch is assigned to this Partner. Please contact Evolution Optical Admin.'; end if;
  elsif v_partner_all_branches and not coalesce(v_version_all_branches,false) then
    select coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]) into v_branch_codes
    from public.voucher_version_branches vvb join public.branches b on b.id=vvb.branch_id
    where vvb.version_id=p_version_id and lower(coalesce(b.status,'active'))='active';
    if coalesce(array_length(v_branch_codes,1),0)=0 then raise exception 'No redemption branch is configured for this voucher version'; end if;
  else
    select coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]) into v_branch_codes
    from public.partner_claim_branches pcb
    join public.voucher_version_branches vvb on vvb.branch_id=pcb.branch_id
    join public.branches b on b.id=pcb.branch_id
    where pcb.partner_id=v_partner_id and vvb.version_id=p_version_id and lower(coalesce(b.status,'active'))='active';
    if coalesce(array_length(v_branch_codes,1),0)=0 then raise exception 'No valid claim branch is shared by this Partner and Voucher Version.'; end if;
  end if;

  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case when v_face_value is not null then 'RM'||trim(to_char(v_face_value,'FM999999990.##'))||' '||v_template_name
                       when v_discount_percent is not null then trim(to_char(v_discount_percent,'FM999999990.##'))||'% '||v_template_name
                       else v_template_name end;

  insert into public.vouchers(partner_id,voucher_code,customer_name,customer_phone,voucher_type,activated_at,expiry_date,status,all_branches,
                              issued_by_user_id,issued_by_name,template_id,version_id,allocation_id,metadata)
  values(v_partner_id,v_voucher_code,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,v_activated_at,v_expiry_date,'valid',
         (v_partner_all_branches and coalesce(v_version_all_branches,false)),auth.uid(),v_actor_name,v_template_id,p_version_id,v_allocation_id,
         jsonb_build_object('issuance_path','multi_voucher','template_code',v_template_code,'version_no',v_version_no))
  returning id,public_token into v_voucher_id,v_public_token;

  if not (v_partner_all_branches and coalesce(v_version_all_branches,false)) then
    insert into public.voucher_branches(voucher_id,branch_id)
    select v_voucher_id,b.id from public.branches b where b.branch_code=any(v_branch_codes) and lower(coalesce(b.status,'active'))='active';
  end if;

  return jsonb_build_object(
    'success',true,'voucher_id',v_voucher_id,'voucher_code',v_voucher_code,'public_token',v_public_token,'partner_id',v_partner_id,
    'template_id',v_template_id,'template_code',v_template_code,'template_name',v_template_name,'version_id',p_version_id,'version_no',v_version_no,
    'version_name',v_version_name,'allocation_id',v_allocation_id,'voucher_type',v_voucher_type,'expiry_date',v_expiry_date,
    'all_branches',(v_partner_all_branches and coalesce(v_version_all_branches,false)),
    'remaining_after_issue',greatest(0,coalesce(v_allocated,0)-coalesce(v_revoked,0)-coalesce(v_issued,0)-1),
    'issued_by_role',v_role,'issued_by_name',v_actor_name
  );
end;$function$;
