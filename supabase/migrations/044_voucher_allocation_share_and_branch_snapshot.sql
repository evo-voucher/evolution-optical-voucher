-- Voucher delivery execution v2
-- Builds on 043_voucher_delivery_policy_snapshot.sql.
-- Business truth:
--   * Voucher Version defines customer offer + presentation.
--   * Allocation defines which Partner receives stock and may choose issue- or allocation-anchored validity.
--   * Issuance freezes presentation/validity and materialises the exact redemption branch set.
--   * Partner claim changes, Version theme changes and later allocations do not rewrite issued Vouchers.

alter table public.vouchers
  add column if not exists branch_scope_snapshotted boolean not null default false;

comment on column public.vouchers.branch_scope_snapshotted is
'True after the exact redemption branch IDs for this issued Voucher have been materialised in voucher_branches.';

-- A theme-specific greeting is additive to the universal Evolution greeting.
-- This preserves the approved default intro while allowing Birthday/Raya/Merdeka/Christmas copy.
create or replace function public.snapshot_voucher_delivery_policy()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_version public.voucher_versions%rowtype;
  v_template public.voucher_templates%rowtype;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_theme_code text;
  v_theme_config jsonb;
  v_default_greeting text := E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.';
  v_occasion text;
begin
  if new.version_id is null then return new; end if;

  select * into v_version from public.voucher_versions where id=new.version_id;
  if not found then raise exception 'Voucher Version does not exist'; end if;
  select * into v_template from public.voucher_templates where id=v_version.template_id;
  if not found then raise exception 'Voucher Template does not exist'; end if;

  if new.allocation_id is not null then
    select * into v_allocation
    from public.partner_voucher_allocations
    where id=new.allocation_id and partner_id=new.partner_id and version_id=new.version_id;
    if not found then raise exception 'Voucher Allocation does not match Partner and Version'; end if;
  end if;

  v_theme_code:=coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default');
  v_theme_config:=case
    when nullif(v_version.theme_override_code,'') is not null then coalesce(v_version.theme_override_config,'{}'::jsonb)
    else coalesce(v_template.theme_config,'{}'::jsonb)
  end;
  v_occasion:=nullif(trim(coalesce(v_version.greeting_text,'')),'');

  new.theme_code_snapshot:=v_theme_code;
  new.theme_config_snapshot:=v_theme_config;
  new.greeting_snapshot:=v_default_greeting||case when v_occasion is not null then E'\n'||v_occasion else '' end;
  new.terms_snapshot:=v_version.terms_text;

  if new.allocation_id is not null and v_allocation.validity_anchor='allocation' then
    if v_allocation.allocation_valid_days is null or v_allocation.valid_until is null then
      raise exception 'Allocation-anchored validity is not fully configured';
    end if;
    if v_allocation.valid_until<now() then raise exception 'Voucher Allocation validity has expired'; end if;
    new.validity_anchor_snapshot:='allocation';
    new.validity_value_snapshot:=v_allocation.allocation_valid_days;
    new.validity_unit_snapshot:='days';
    new.expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
  else
    new.validity_anchor_snapshot:='issue';
    if v_version.validity_mode='months' then
      new.validity_value_snapshot:=v_version.valid_months;
      new.validity_unit_snapshot:='months';
    elsif v_version.validity_mode='days' then
      new.validity_value_snapshot:=v_version.valid_days;
      new.validity_unit_snapshot:='days';
    else
      new.validity_value_snapshot:=null;
      new.validity_unit_snapshot:='fixed';
    end if;
  end if;
  return new;
end;
$$;

-- Prevent an issued materialised branch set from being reopened for mutation.
create or replace function public.guard_voucher_branch_snapshot_flag()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.branch_scope_snapshotted and not new.branch_scope_snapshotted then
    raise exception 'Issued Voucher branch snapshot is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists vouchers_guard_branch_snapshot_flag on public.vouchers;
create trigger vouchers_guard_branch_snapshot_flag
before update on public.vouchers
for each row execute function public.guard_voucher_branch_snapshot_flag();

create or replace function public.guard_voucher_branch_snapshot_rows()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_voucher_id uuid;
begin
  v_voucher_id:=coalesce(new.voucher_id,old.voucher_id);
  if exists(select 1 from public.vouchers v where v.id=v_voucher_id and v.branch_scope_snapshotted) then
    raise exception 'Issued Voucher branch snapshot is immutable';
  end if;
  return coalesce(new,old);
end;
$$;

drop trigger if exists voucher_branches_guard_snapshot_rows on public.voucher_branches;
create trigger voucher_branches_guard_snapshot_rows
before insert or update or delete on public.voucher_branches
for each row execute function public.guard_voucher_branch_snapshot_rows();

-- Admin publishes a new immutable Version. Old publish RPC stays intact for compatibility.
create or replace function public.admin_publish_voucher_version_v2(
  p_template_id uuid,
  p_version_name text default null,
  p_face_value numeric default null,
  p_discount_percent numeric default null,
  p_validity_mode text default 'days_after_issue',
  p_valid_days integer default null,
  p_valid_months integer default null,
  p_valid_until date default null,
  p_min_spend numeric default null,
  p_max_discount numeric default null,
  p_usage_limit integer default 1,
  p_transferable boolean default true,
  p_terms_text text default null,
  p_supply_limit integer default null,
  p_all_branches boolean default false,
  p_theme_code text default null,
  p_theme_config jsonb default '{}'::jsonb,
  p_greeting_text text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_no integer;
  v_mode text;
  v_template_status text;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select vt.status into v_template_status
  from public.voucher_templates vt where vt.id=p_template_id for update;
  if not found or v_template_status='archived' then raise exception 'Voucher template not found or archived'; end if;

  v_mode:=case lower(trim(coalesce(p_validity_mode,'')))
    when 'days_after_issue' then 'days'
    when 'days' then 'days'
    when 'calendar_months_after_issue' then 'months'
    when 'months' then 'months'
    when 'fixed' then 'fixed'
    else null end;
  if v_mode is null then raise exception 'Unsupported validity mode'; end if;
  if v_mode='days' and (p_valid_days is null or p_valid_days<1) then raise exception 'Valid days must be at least 1'; end if;
  if v_mode='months' and (p_valid_months is null or p_valid_months<1) then raise exception 'Valid months must be at least 1'; end if;
  if v_mode='fixed' and p_valid_until is null then raise exception 'Fixed validity requires valid_until'; end if;
  if p_usage_limit is null or p_usage_limit<1 then raise exception 'Usage limit must be at least 1'; end if;

  select coalesce(max(version_no),0)+1 into v_no
  from public.voucher_versions where template_id=p_template_id;

  insert into public.voucher_versions(
    template_id,version_no,version_name,face_value,discount_percent,
    validity_mode,valid_days,valid_months,valid_until,min_spend,max_discount,
    usage_limit,transferable,terms_text,supply_limit,all_branches,
    theme_override_code,theme_override_config,greeting_text,status,effective_from,created_by
  ) values (
    p_template_id,v_no,nullif(trim(coalesce(p_version_name,'')),''),p_face_value,p_discount_percent,
    v_mode,case when v_mode='days' then p_valid_days end,case when v_mode='months' then p_valid_months end,
    case when v_mode='fixed' then p_valid_until end,p_min_spend,p_max_discount,
    p_usage_limit,coalesce(p_transferable,true),nullif(trim(coalesce(p_terms_text,'')),''),p_supply_limit,
    coalesce(p_all_branches,false),nullif(trim(coalesce(p_theme_code,'')),''),coalesce(p_theme_config,'{}'::jsonb),
    nullif(trim(coalesce(p_greeting_text,'')),''),'active',now(),(select auth.uid())
  ) returning id into v_id;

  update public.voucher_templates
  set current_version_id=v_id,status='active',updated_at=now()
  where id=p_template_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
  values((select auth.uid()),'voucher_version_published','voucher_version',v_id::text,
    jsonb_build_object('template_id',p_template_id,'version_no',v_no,'validity_mode',v_mode,
      'valid_days',case when v_mode='days' then p_valid_days end,
      'valid_months',case when v_mode='months' then p_valid_months end,
      'theme_code',nullif(trim(coalesce(p_theme_code,'')),'')));
  return v_id;
end;
$$;

revoke all on function public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text) from public, anon;
grant execute on function public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text) to authenticated;

-- Allocation validity is Partner-specific. FROM_ALLOCATION always creates a new batch
-- so a later top-up cannot reset the original 90/100/etc-day clock.
create or replace function public.admin_engine_allocate_v2(
  p_partner_id uuid,
  p_version_id uuid,
  p_quantity integer,
  p_validity_anchor text default 'issue',
  p_allocation_valid_days integer default null,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_actor_name text;
  v_template_id uuid;
  v_anchor text;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_created boolean:=false;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
begin
  if p_partner_id is null or p_version_id is null then raise exception 'Partner and Version are required'; end if;
  if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be positive'; end if;
  v_anchor:=case lower(trim(coalesce(p_validity_anchor,'')))
    when 'issue' then 'issue' when 'from_issue' then 'issue'
    when 'allocation' then 'allocation' when 'from_allocation' then 'allocation'
    else null end;
  if v_anchor is null then raise exception 'Unsupported validity anchor'; end if;
  if v_anchor='allocation' and (p_allocation_valid_days is null or p_allocation_valid_days<1) then
    raise exception 'Allocation validity days must be at least 1';
  end if;

  if public.is_voucher_admin() then v_actor:=(select auth.uid());
  elsif public.is_trusted_service_role() then v_actor:=p_actor_user_id;
  else raise exception 'Admin access required'; end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
  from public.admin_users a where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;
  if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then raise exception 'Active Partner not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));
  select vv.template_id into v_template_id
  from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active';
  if not found then raise exception 'Active Voucher Version not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_version_id::text,4401));

  if v_anchor='issue' then
    select * into v_allocation
    from public.partner_voucher_allocations a
    where a.partner_id=p_partner_id and a.version_id=p_version_id
      and a.status='active' and a.validity_anchor='issue'
    order by a.created_at desc limit 1 for update;
    if found then
      update public.partner_voucher_allocations
      set quantity_allocated=quantity_allocated+p_quantity,updated_at=now()
      where id=v_allocation.id returning * into v_allocation;
    else
      insert into public.partner_voucher_allocations(
        partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,
        allocation_valid_days,valid_from,valid_until,created_by
      ) values (p_partner_id,p_version_id,p_quantity,0,'active','issue',null,null,null,v_actor)
      returning * into v_allocation;
      v_created:=true;
    end if;
  else
    v_valid_from:=now();
    v_valid_until:=now()+make_interval(days=>p_allocation_valid_days);
    insert into public.partner_voucher_allocations(
      partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,
      allocation_valid_days,valid_from,valid_until,created_by
    ) values (p_partner_id,p_version_id,p_quantity,0,'active','allocation',p_allocation_valid_days,v_valid_from,v_valid_until,v_actor)
    returning * into v_allocation;
    v_created:=true;
  end if;

  insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by,created_at,updated_at)
  values(p_partner_id,v_template_id,'active','allocation',v_actor,now(),now())
  on conflict(partner_id,template_id) do update set status='active',quota_type='allocation',updated_at=now();

  insert into public.voucher_allocation_events(allocation_id,partner_id,version_id,event_type,quantity,actor_user_id)
  values(v_allocation.id,p_partner_id,p_version_id,case when v_created then 'allocated' else 'increased' end,p_quantity,v_actor);

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data)
  values(v_actor,v_actor_name,'voucher_allocation_changed','voucher_allocation',v_allocation.id::text,p_partner_id,
    jsonb_build_object('version_id',p_version_id,'quantity_added',p_quantity,'quantity_allocated',v_allocation.quantity_allocated,
      'validity_anchor',v_allocation.validity_anchor,'allocation_valid_days',v_allocation.allocation_valid_days,
      'valid_from',v_allocation.valid_from,'valid_until',v_allocation.valid_until,'created',v_created));

  return jsonb_build_object('success',true,'allocation_id',v_allocation.id,'partner_id',p_partner_id,'version_id',p_version_id,
    'quantity_added',p_quantity,'quantity_allocated',v_allocation.quantity_allocated,'quantity_revoked',v_allocation.quantity_revoked,
    'validity_anchor',v_allocation.validity_anchor,'allocation_valid_days',v_allocation.allocation_valid_days,
    'valid_from',v_allocation.valid_from,'valid_until',v_allocation.valid_until,'created',v_created);
end;
$$;

revoke all on function public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid) from public, anon;
grant execute on function public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid) to authenticated, service_role;

-- Canonical issue path: choose a remaining batch. Allocation-anchored batches use
-- earliest-expiry-first; issue-anchored stock remains compatible with the old model.
create or replace function public.issue_engine_voucher(
  p_version_id uuid,p_customer_name text,p_customer_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_partner_id uuid; v_partner_role text; v_staff_name text; v_staff_access_enabled boolean; v_partner_status text;
  v_template public.voucher_templates%rowtype; v_version public.voucher_versions%rowtype; v_allocation public.partner_voucher_allocations%rowtype;
  v_issued integer:=0; v_issue_date date:=(now() at time zone 'Asia/Kuala_Lumpur')::date; v_expiry_date date;
  v_partner_all_branches boolean:=false; v_final_all_branches boolean:=false; v_voucher_id uuid; v_voucher_code text; v_public_token uuid;
  v_voucher_type text; v_branch_count integer:=0;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Customer name is required'; end if;

  select pu.partner_id,pu.role,pu.staff_name,p.staff_access_enabled,p.status
  into v_partner_id,v_partner_role,v_staff_name,v_staff_access_enabled,v_partner_status
  from public.partner_users pu join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid and pu.status='active' and pu.removed_at is null and pu.role in ('partner_admin','partner_staff') limit 1;
  if v_partner_id is null or v_partner_status<>'active' then raise exception 'Active Partner account not found'; end if;
  if v_partner_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;

  select * into v_version from public.voucher_versions vv where vv.id=p_version_id and vv.status='active' limit 1;
  if not found then raise exception 'Active voucher version not found'; end if;
  select * into v_template from public.voucher_templates vt where vt.id=v_version.template_id and vt.status='active' limit 1;
  if not found then raise exception 'Active voucher template not found'; end if;

  if not exists(select 1 from public.partner_voucher_access pva
    where pva.partner_id=v_partner_id and pva.template_id=v_template.id and pva.status='active'
      and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())) then
    raise exception 'This Partner is not authorised for this voucher type';
  end if;

  select a.* into v_allocation
  from public.partner_voucher_allocations a
  where a.partner_id=v_partner_id and a.version_id=p_version_id and a.status='active'
    and (a.valid_from is null or a.valid_from<=now()) and (a.valid_until is null or a.valid_until>=now())
    and (a.quantity_allocated-a.quantity_revoked)>(select count(*) from public.vouchers vx where vx.allocation_id=a.id)
  order by case when a.validity_anchor='allocation' then 0 else 1 end,
           case when a.validity_anchor='allocation' then a.valid_until end asc nulls last,
           a.created_at asc
  limit 1 for update of a;
  if not found then raise exception 'No active allocation is available for this voucher type'; end if;

  select count(*) into v_issued from public.vouchers v where v.allocation_id=v_allocation.id;
  if v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued<=0 then raise exception 'Voucher allocation limit reached'; end if;
  if v_version.supply_limit is not null and (select count(*) from public.vouchers v where v.version_id=v_version.id)>=v_version.supply_limit then
    raise exception 'Voucher version supply limit reached';
  end if;

  if v_allocation.validity_anchor='allocation' then
    if v_allocation.valid_until is null then raise exception 'Allocation expiry is not configured'; end if;
    v_expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
  else
    case v_version.validity_mode
      when 'fixed' then
        if v_version.valid_from is not null and v_issue_date<v_version.valid_from then raise exception 'Voucher campaign has not started'; end if;
        if v_version.valid_until is null or v_issue_date>v_version.valid_until then raise exception 'Voucher campaign has ended'; end if;
        v_expiry_date:=v_version.valid_until;
      when 'days' then v_expiry_date:=v_issue_date+v_version.valid_days;
      when 'months' then v_expiry_date:=(v_issue_date+make_interval(months=>v_version.valid_months))::date;
      else raise exception 'Voucher validity is not configured';
    end case;
  end if;

  select coalesce(s.all_branches,false) into v_partner_all_branches from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=false; end if;
  v_final_all_branches:=v_partner_all_branches and v_version.all_branches;

  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case when v_version.face_value is not null then 'RM'||trim(to_char(v_version.face_value,'FM999999990.##'))||' '||v_template.template_name
    when v_version.discount_percent is not null then trim(to_char(v_version.discount_percent,'FM999999990.##'))||'% '||v_template.template_name else v_template.template_name end;

  insert into public.vouchers(voucher_code,partner_id,customer_name,customer_phone,voucher_type,status,expiry_date,
    issued_by_user_id,issued_by_name,all_branches,usage_limit,usage_count,template_id,version_id,allocation_id,metadata,branch_scope_snapshotted)
  values(v_voucher_code,v_partner_id,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,'active',v_expiry_date,
    v_uid,coalesce(nullif(trim(coalesce(v_staff_name,'')),''),case when v_partner_role='partner_admin' then 'Partner Admin' else 'Partner Staff' end),
    v_final_all_branches,v_version.usage_limit,0,v_template.id,v_version.id,v_allocation.id,
    jsonb_build_object('issuance_path','engine_v2','template_code',v_template.template_code,'version_no',v_version.version_no),false)
  returning id,public_token,expiry_date into v_voucher_id,v_public_token,v_expiry_date;

  if v_partner_all_branches and v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id) select v_voucher_id,b.id from public.branches b where b.status='active';
  elsif not v_partner_all_branches and v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id)
    select v_voucher_id,pcb.branch_id from public.partner_claim_branches pcb join public.branches b on b.id=pcb.branch_id
    where pcb.partner_id=v_partner_id and b.status='active';
  elsif v_partner_all_branches and not v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id)
    select v_voucher_id,vvb.branch_id from public.voucher_version_branches vvb join public.branches b on b.id=vvb.branch_id
    where vvb.version_id=v_version.id and b.status='active';
  else
    insert into public.voucher_branches(voucher_id,branch_id)
    select v_voucher_id,pcb.branch_id from public.partner_claim_branches pcb
    join public.voucher_version_branches vvb on vvb.branch_id=pcb.branch_id join public.branches b on b.id=pcb.branch_id
    where pcb.partner_id=v_partner_id and vvb.version_id=v_version.id and b.status='active';
  end if;
  select count(*) into v_branch_count from public.voucher_branches vb where vb.voucher_id=v_voucher_id;
  if v_branch_count=0 then raise exception 'No valid redemption branch is shared by Partner and Voucher Version'; end if;
  update public.vouchers set branch_scope_snapshotted=true,updated_at=now() where id=v_voucher_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,coalesce(v_staff_name,v_partner_role),'engine_voucher_issued','voucher',v_voucher_id::text,v_partner_id,
    jsonb_build_object('voucher_code',v_voucher_code,'template_code',v_template.template_code,'version_no',v_version.version_no,
      'validity_anchor',v_allocation.validity_anchor,'expiry_date',v_expiry_date,'branch_snapshot_count',v_branch_count),
    jsonb_build_object('allocation_id',v_allocation.id,'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1)));

  return jsonb_build_object('success',true,'voucher_id',v_voucher_id,'voucher_code',v_voucher_code,'public_token',v_public_token,
    'partner_id',v_partner_id,'template_id',v_template.id,'template_code',v_template.template_code,'template_name',v_template.template_name,
    'version_id',v_version.id,'version_no',v_version.version_no,'version_name',v_version.version_name,'voucher_type',v_voucher_type,
    'expiry_date',v_expiry_date,'validity_anchor',v_allocation.validity_anchor,'all_branches',v_final_all_branches,
    'branch_snapshot_count',v_branch_count,'usage_limit',v_version.usage_limit,
    'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),
    'theme_code',coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default'),
    'theme_config',case when nullif(v_version.theme_override_code,'') is not null then v_version.theme_override_config else v_template.theme_config end);
end;
$$;

revoke all on function public.issue_engine_voucher(uuid,text,text) from public, anon;
grant execute on function public.issue_engine_voucher(uuid,text,text) to authenticated;

-- Redemption obeys the frozen branch snapshot for new Vouchers. Legacy all-branch
-- records without a snapshot retain compatibility behavior.
create or replace function public.redeem_voucher(p_voucher_code text,p_notes text default null,p_branch_code text default null,p_redeem_method text default 'qr')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=(select auth.uid()); v_staff public.staff_users%rowtype; v_voucher public.vouchers%rowtype;
  v_branch_id uuid; v_branch_name text; v_allowed boolean:=false; v_new_usage integer; v_now timestamptz:=now();
  v_today date:=(now() at time zone 'Asia/Kuala_Lumpur')::date; v_redemption_id uuid; v_method text;
begin
  if v_uid is null then return jsonb_build_object('success',false,'error','Authentication required'); end if;
  v_method:=lower(trim(coalesce(p_redeem_method,'qr')));
  if v_method not in ('qr','manual_code','admin') then return jsonb_build_object('success',false,'error','Invalid redeem method'); end if;
  select * into v_staff from public.staff_users su where su.user_id=v_uid and su.status='active' limit 1;
  if not found then return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended'); end if;
  if v_staff.role='all_branch_manager' then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where upper(b.branch_code)=upper(trim(p_branch_code)) and b.status='active' limit 1;
  else
    if v_staff.branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b where b.id=v_staff.branch_id and b.status='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;
  select * into v_voucher from public.vouchers v where upper(v.voucher_code)=upper(trim(p_voucher_code)) for update;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  if v_voucher.status='revoked' then return jsonb_build_object('success',false,'error','Voucher has been revoked','status',v_voucher.status); end if;
  if v_voucher.status='expired' or v_voucher.expiry_date<v_today then
    update public.vouchers set status=case when status='active' then 'expired' else status end,updated_at=v_now where id=v_voucher.id;
    return jsonb_build_object('success',false,'error','Voucher has expired','status','expired');
  end if;
  if v_voucher.status='redeemed' or v_voucher.usage_count>=v_voucher.usage_limit then return jsonb_build_object('success',false,'error','Voucher has already been fully redeemed','status','redeemed'); end if;
  if v_voucher.status<>'active' then return jsonb_build_object('success',false,'error','Voucher is not active','status',v_voucher.status); end if;

  if v_voucher.branch_scope_snapshotted then
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  elsif v_voucher.all_branches then v_allowed:=true;
  else select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  end if;
  if not v_allowed then return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch'); end if;

  v_new_usage:=v_voucher.usage_count+1;
  insert into public.redemptions(voucher_id,partner_id,branch_id,staff_user_id,staff_name_snapshot,redeem_method,status,redeemed_at,notes)
  values(v_voucher.id,v_voucher.partner_id,v_branch_id,v_uid,v_staff.staff_name,v_method,'completed',v_now,nullif(trim(coalesce(p_notes,'')),'')) returning id into v_redemption_id;
  update public.vouchers set usage_count=v_new_usage,status=case when v_new_usage>=usage_limit then 'redeemed' else 'active' end,updated_at=v_now where id=v_voucher.id;
  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,v_staff.staff_name,'voucher_redeemed','redemption',v_redemption_id::text,v_voucher.partner_id,
    jsonb_build_object('voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'branch_id',v_branch_id,'branch_name',v_branch_name,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit),
    jsonb_build_object('redeem_method',v_method,'branch_scope_source',case when v_voucher.branch_scope_snapshotted then 'voucher_snapshot' else 'legacy' end));
  return jsonb_build_object('success',true,'redemption_id',v_redemption_id,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,
    'customer_name',v_voucher.customer_name,'voucher_type',v_voucher.voucher_type,'branch_id',v_branch_id,'branch_name',v_branch_name,
    'staff_name',v_staff.staff_name,'redeemed_at',v_now,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit,
    'remaining_uses',greatest(0,v_voucher.usage_limit-v_new_usage),'status',case when v_new_usage>=v_voucher.usage_limit then 'redeemed' else 'active' end);
end;
$$;
revoke all on function public.redeem_voucher(text,text,text,text) from public, anon;
grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;

-- Public view uses frozen delivery snapshots and frozen branch membership for new Vouchers.
create or replace function public.get_public_voucher(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'success',true,'voucher_code',v.voucher_code,'voucher_type',v.voucher_type,'customer_name',v.customer_name,'partner_name',p.partner_name,
    'expiry_date',v.expiry_date,
    'status',case when v.status='redeemed' then 'redeemed' when v.status='revoked' then 'revoked' when v.status='expired' then 'expired'
      when v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired' when v.status='active' then 'valid' else v.status end,
    'canonical_status',v.status,'issued_at',v.issued_at,'all_branches',v.all_branches,
    'validity_anchor',v.validity_anchor_snapshot,'validity_value',v.validity_value_snapshot,'validity_unit',v.validity_unit_snapshot,
    'theme_code',coalesce(v.theme_code_snapshot,'default'),'theme_config',coalesce(v.theme_config_snapshot,'{}'::jsonb),
    'greeting',coalesce(nullif(v.greeting_snapshot,''),E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.'),'terms_text',v.terms_snapshot,
    'branches',coalesce(
      case when v.branch_scope_snapshotted or not v.all_branches then
        (select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
         from public.voucher_branches vb join public.branches b on b.id=vb.branch_id where vb.voucher_id=v.id and b.status='active')
      else
        (select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
         from public.branches b where b.status='active') end,'[]'::jsonb)
  ) into v_result
  from public.vouchers v join public.partners p on p.id=v.partner_id where v.public_token=p_token limit 1;
  if v_result is null then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  return v_result;
end;
$$;
revoke all on function public.get_public_voucher(uuid) from public;
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;

-- Partner/Admin canonical share payload. Frontend appends the customer voucher URL.
create or replace function public.get_partner_voucher_share(p_voucher_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_partner_id uuid; v_code text; v_type text; v_expiry date; v_greeting text; v_branches jsonb; v_branch_text text; v_message text;
begin
  select v.partner_id,v.voucher_code,v.voucher_type,v.expiry_date,
         coalesce(nullif(v.greeting_snapshot,''),E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.')
  into v_partner_id,v_code,v_type,v_expiry,v_greeting
  from public.vouchers v where v.id=p_voucher_id;
  if not found then raise exception 'Voucher not found'; end if;
  if not public.is_voucher_admin() and public.current_partner_id() is distinct from v_partner_id then raise exception 'Voucher access denied'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
         coalesce(string_agg('Evolution Optical – '||b.branch_name||E'\n'||coalesce(b.address,'')||case when nullif(b.phone,'') is not null then E'\n'||b.phone else '' end,E'\n\n' order by b.branch_name),'')
  into v_branches,v_branch_text
  from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=p_voucher_id and b.status='active';

  v_message:=v_greeting||E'\n\nVoucher: '||v_type||E'\nValid until: '||to_char(v_expiry,'DD Mon YYYY')||E'\n\nRedeem at:\n'||v_branch_text;
  return jsonb_build_object('success',true,'voucher_id',p_voucher_id,'voucher_code',v_code,'voucher_type',v_type,'expiry_date',v_expiry,
    'greeting',v_greeting,'branches',v_branches,'message_body',v_message);
end;
$$;
revoke all on function public.get_partner_voucher_share(uuid) from public, anon;
grant execute on function public.get_partner_voucher_share(uuid) to authenticated;
