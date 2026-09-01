-- Converge customer-aware voucher issuing with the current production baseline.
-- Production remains read-only reference.

create or replace function public.normalize_customer_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if v_digits='' then return null; end if;
  if v_digits like '60%' and length(v_digits) between 10 and 12 then
    return '0' || substring(v_digits from 3);
  end if;
  return v_digits;
end;
$function$;

create or replace function public.attach_voucher_customer()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_norm text;
  v_customer_id uuid;
begin
  if new.partner_id is null or nullif(trim(coalesce(new.customer_name,'')),'') is null then
    return new;
  end if;

  v_norm := public.normalize_customer_phone(new.customer_phone);

  if v_norm is not null then
    insert into public.partner_customers(
      partner_id,customer_name,customer_phone,normalized_phone,first_seen_at,last_seen_at,created_at,updated_at
    ) values (
      new.partner_id,trim(new.customer_name),nullif(trim(coalesce(new.customer_phone,'')),''),v_norm,
      coalesce(new.issued_at,now()),coalesce(new.issued_at,now()),now(),now()
    )
    on conflict (partner_id,normalized_phone) where normalized_phone is not null
    do update set
      customer_name=excluded.customer_name,
      customer_phone=excluded.customer_phone,
      last_seen_at=greatest(public.partner_customers.last_seen_at,excluded.last_seen_at),
      updated_at=now()
    returning id into v_customer_id;
  elsif new.customer_id is not null then
    update public.partner_customers
      set customer_name=trim(new.customer_name),
          customer_phone=nullif(trim(coalesce(new.customer_phone,'')),''),
          last_seen_at=greatest(last_seen_at,coalesce(new.issued_at,now())),
          updated_at=now()
      where id=new.customer_id and partner_id=new.partner_id
      returning id into v_customer_id;
  else
    insert into public.partner_customers(
      partner_id,customer_name,customer_phone,normalized_phone,first_seen_at,last_seen_at
    ) values (
      new.partner_id,trim(new.customer_name),nullif(trim(coalesce(new.customer_phone,'')),''),null,
      coalesce(new.issued_at,now()),coalesce(new.issued_at,now())
    ) returning id into v_customer_id;
  end if;

  new.customer_id := v_customer_id;
  return new;
end;
$function$;

create or replace function public.guard_partner_global_voucher_quota()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare v_limit integer; v_issued bigint;
begin
  if new.partner_id is null then raise exception 'Voucher partner_id is required'; end if;
  select p.voucher_limit into v_limit from public.partners p where p.id=new.partner_id and p.status='active' for update;
  if not found then raise exception 'Active Partner not found'; end if;
  if v_limit=0 then return new; end if;
  select count(*) into v_issued from public.vouchers v where v.partner_id=new.partner_id;
  if v_issued >= v_limit then raise exception 'Partner voucher limit reached'; end if;
  return new;
end;
$function$;

drop trigger if exists vouchers_guard_global_partner_quota on public.vouchers;

drop function if exists public.issue_engine_voucher(uuid,text,text);

create or replace function public.issue_engine_voucher(p_version_id uuid, p_customer_name text, p_customer_phone text default null::text, p_partner_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
  v_validity_value integer;
  v_validity_unit text;
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

  if v_allocation.validity_value is not null and v_allocation.validity_unit in ('days','months') then
    v_validity_value:=v_allocation.validity_value;
    v_validity_unit:=v_allocation.validity_unit;
    if v_allocation.validity_anchor='allocation' then
      if v_allocation.valid_until is null then raise exception 'Allocation expiry is not configured'; end if;
      v_expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
    else
      v_expiry_date:=case v_validity_unit
        when 'days' then v_issue_date+v_validity_value
        when 'months' then (v_issue_date+make_interval(months=>v_validity_value))::date
      end;
    end if;
  elsif v_allocation.validity_anchor='allocation' then
    if v_allocation.valid_until is null then raise exception 'Allocation expiry is not configured'; end if;
    v_validity_value:=v_allocation.allocation_valid_days;
    v_validity_unit:='days';
    v_expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
  else
    case v_version.validity_mode
      when 'fixed' then
        if v_version.valid_from is not null and v_issue_date<v_version.valid_from then raise exception 'Voucher campaign has not started'; end if;
        if v_version.valid_until is null or v_issue_date>v_version.valid_until then raise exception 'Voucher campaign has ended'; end if;
        v_expiry_date:=v_version.valid_until;
        v_validity_value:=null; v_validity_unit:='fixed';
      when 'days' then v_validity_value:=v_version.valid_days; v_validity_unit:='days'; v_expiry_date:=v_issue_date+v_version.valid_days;
      when 'months' then v_validity_value:=v_version.valid_months; v_validity_unit:='months'; v_expiry_date:=(v_issue_date+make_interval(months=>v_version.valid_months))::date;
      else raise exception 'Voucher validity is not configured';
    end case;
  end if;

  select coalesce(s.all_branches,false) into v_partner_all_branches from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=false; end if;
  v_final_all_branches:=v_partner_all_branches and v_version.all_branches;
  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case when v_version.face_value is not null then 'RM'||trim(to_char(v_version.face_value,'FM999999990.##'))||' '||v_template.template_name when v_version.discount_percent is not null then trim(to_char(v_version.discount_percent,'FM999999990.##'))||'% '||v_template.template_name else v_template.template_name end;

  insert into public.vouchers(voucher_code,partner_id,customer_name,customer_phone,voucher_type,status,expiry_date,issued_by_user_id,issued_by_name,all_branches,usage_limit,usage_count,template_id,version_id,allocation_id,metadata,branch_scope_snapshotted,validity_anchor_snapshot,validity_value_snapshot,validity_unit_snapshot)
  values(v_voucher_code,v_partner_id,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,'active',v_expiry_date,v_uid,v_staff_name,v_final_all_branches,v_version.usage_limit,0,v_template.id,v_version.id,v_allocation.id,jsonb_build_object('issuance_path','engine','template_code',v_template.template_code,'version_no',v_version.version_no,'actor_realm',v_ctx->>'actor_realm'),false,v_allocation.validity_anchor,v_validity_value,v_validity_unit)
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
  values(v_uid,v_staff_name,'engine_voucher_issued','voucher',v_voucher_id::text,v_partner_id,jsonb_build_object('voucher_code',v_voucher_code,'template_code',v_template.template_code,'version_no',v_version.version_no,'validity_anchor',v_allocation.validity_anchor,'validity_value',v_validity_value,'validity_unit',v_validity_unit,'expiry_date',v_expiry_date,'branch_snapshot_count',v_branch_count),jsonb_build_object('allocation_id',v_allocation.id,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),'actor_realm',v_ctx->>'actor_realm'));

  return jsonb_build_object('success',true,'voucher_id',v_voucher_id,'voucher_code',v_voucher_code,'public_token',v_public_token,'partner_id',v_partner_id,'template_id',v_template.id,'template_code',v_template.template_code,'template_name',v_template.template_name,'version_id',v_version.id,'version_no',v_version.version_no,'version_name',v_version.version_name,'voucher_type',v_voucher_type,'expiry_date',v_expiry_date,'validity_anchor',v_allocation.validity_anchor,'validity_value',v_validity_value,'validity_unit',v_validity_unit,'all_branches',v_final_all_branches,'branch_snapshot_count',v_branch_count,'usage_limit',v_version.usage_limit,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),'theme_code',coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default'),'theme_config',case when nullif(v_version.theme_override_code,'') is not null then v_version.theme_override_config else v_template.theme_config end,'actor_realm',v_ctx->>'actor_realm');
end;
$function$;

create or replace function public.issue_engine_voucher_with_customer(p_version_id uuid, p_customer_name text, p_customer_phone text default null::text, p_partner_id uuid default null::uuid, p_customer_birthday date default null::date, p_customer_district text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
  v_voucher_id uuid;
  v_partner_id uuid;
  v_customer_id uuid;
  v_phone_required boolean:=false;
  v_birthday_required boolean:=false;
  v_district_required boolean:=false;
  v_district text:=nullif(trim(coalesce(p_customer_district,'')),'');
begin
  select phone_required,birthday_required,district_required
    into v_phone_required,v_birthday_required,v_district_required
  from public.system_customer_field_settings where singleton_id=1;
  if coalesce(v_phone_required,false) and nullif(trim(coalesce(p_customer_phone,'')),'') is null then raise exception 'Customer phone is required'; end if;
  if coalesce(v_birthday_required,false) and p_customer_birthday is null then raise exception 'Customer birthday is required'; end if;
  if coalesce(v_district_required,false) and v_district is null then raise exception 'Customer district is required'; end if;
  if p_customer_birthday is not null and p_customer_birthday>(now() at time zone 'Asia/Kuala_Lumpur')::date then raise exception 'Customer birthday cannot be in the future'; end if;
  if v_district is not null and not exists(select 1 from public.customer_districts d where d.district_name=v_district and d.status='active') then raise exception 'Invalid or inactive customer district'; end if;

  v_result:=public.issue_engine_voucher(p_version_id=>p_version_id,p_customer_name=>p_customer_name,p_customer_phone=>p_customer_phone,p_partner_id=>p_partner_id);
  v_voucher_id:=nullif(v_result->>'voucher_id','')::uuid;
  v_partner_id:=nullif(v_result->>'partner_id','')::uuid;
  if v_voucher_id is null or v_partner_id is null then raise exception 'Voucher issuance did not return a valid customer context'; end if;
  select v.customer_id into v_customer_id from public.vouchers v where v.id=v_voucher_id and v.partner_id=v_partner_id;
  if v_customer_id is null then raise exception 'Customer master link was not created'; end if;
  update public.partner_customers pc
     set birth_date=coalesce(p_customer_birthday,pc.birth_date),
         district=coalesce(v_district,pc.district),
         updated_at=now()
   where pc.id=v_customer_id and pc.partner_id=v_partner_id;
  return v_result||jsonb_build_object('customer_id',v_customer_id);
end;
$function$;

revoke all on function public.normalize_customer_phone(text) from public, anon, authenticated, service_role;
revoke all on function public.attach_voucher_customer() from public, anon, authenticated, service_role;
revoke all on function public.guard_partner_global_voucher_quota() from public, anon, authenticated, service_role;
revoke all on function public.issue_engine_voucher(uuid,text,text,uuid) from public, anon, authenticated, service_role;
grant execute on function public.issue_engine_voucher(uuid,text,text,uuid) to service_role;
revoke all on function public.issue_engine_voucher_with_customer(uuid,text,text,uuid,date,text) from public, anon, authenticated, service_role;
grant execute on function public.issue_engine_voucher_with_customer(uuid,text,text,uuid,date,text) to authenticated, service_role;
