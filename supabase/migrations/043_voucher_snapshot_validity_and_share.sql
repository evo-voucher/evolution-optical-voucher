-- Voucher lifecycle v2: validity anchors, frozen presentation snapshots, frozen branch scope,
-- and canonical WhatsApp share payloads.
-- Root rule: issued vouchers are historical facts. Later Template/Version/Partner changes
-- must not rewrite the customer-facing voucher that already exists.

alter table public.voucher_versions
  add column if not exists validity_anchor text not null default 'issue',
  add column if not exists occasion_greeting text;

alter table public.vouchers
  add column if not exists presentation_snapshot jsonb not null default '{}'::jsonb;

alter table public.voucher_versions
  drop constraint if exists voucher_versions_validity_anchor_check;
alter table public.voucher_versions
  add constraint voucher_versions_validity_anchor_check
  check (validity_anchor in ('issue','allocation'));

alter table public.voucher_versions
  drop constraint if exists voucher_versions_allocation_validity_check;
alter table public.voucher_versions
  add constraint voucher_versions_allocation_validity_check
  check (
    validity_anchor <> 'allocation'
    or (validity_mode='days' and valid_days is not null and valid_days > 0)
  );

comment on column public.voucher_versions.validity_anchor is
'issue = validity starts when Partner/Partner Staff issues to customer; allocation = validity starts when Admin creates that allocation batch.';
comment on column public.voucher_versions.occasion_greeting is
'Optional theme/occasion-specific WhatsApp greeting. The universal share intro is snapshotted at issuance.';
comment on column public.vouchers.presentation_snapshot is
'Immutable-at-issuance customer presentation snapshot: theme, greeting, terms, validity semantics and version identity.';

-- New publish boundary. The original publish RPC remains available for compatibility;
-- new UI should call v2 when using allocation-anchored validity, theme config or greetings.
create or replace function public.admin_publish_voucher_version_v2(
  p_template_id uuid,
  p_version_name text default null,
  p_face_value numeric default null,
  p_discount_percent numeric default null,
  p_validity_anchor text default 'issue',
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
  p_theme_override_code text default null,
  p_theme_override_config jsonb default '{}'::jsonb,
  p_occasion_greeting text default null
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
  v_anchor text;
  v_template_status text;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select vt.status into v_template_status
  from public.voucher_templates vt
  where vt.id=p_template_id
  for update;
  if not found or v_template_status='archived' then
    raise exception 'Voucher template not found or archived';
  end if;

  v_anchor := case lower(trim(coalesce(p_validity_anchor,'')))
    when 'issue' then 'issue'
    when 'from_issue' then 'issue'
    when 'allocation' then 'allocation'
    when 'from_allocation' then 'allocation'
    else null end;
  if v_anchor is null then raise exception 'Unsupported validity anchor'; end if;

  v_mode := case lower(trim(coalesce(p_validity_mode,'')))
    when 'days_after_issue' then 'days'
    when 'days' then 'days'
    when 'calendar_months_after_issue' then 'months'
    when 'months' then 'months'
    when 'fixed' then 'fixed'
    else null end;
  if v_mode is null then raise exception 'Unsupported validity mode'; end if;

  if v_anchor='allocation' and v_mode<>'days' then
    raise exception 'Allocation-anchored validity currently supports days only';
  end if;
  if v_mode='days' and (p_valid_days is null or p_valid_days<1) then raise exception 'Valid days must be at least 1'; end if;
  if v_mode='months' and (p_valid_months is null or p_valid_months<1) then raise exception 'Valid months must be at least 1'; end if;
  if v_mode='fixed' and p_valid_until is null then raise exception 'Fixed validity requires valid_until'; end if;
  if p_usage_limit is null or p_usage_limit<1 then raise exception 'Usage limit must be at least 1'; end if;

  select coalesce(max(version_no),0)+1 into v_no
  from public.voucher_versions
  where template_id=p_template_id;

  insert into public.voucher_versions(
    template_id,version_no,version_name,face_value,discount_percent,
    validity_anchor,validity_mode,valid_days,valid_months,valid_until,
    min_spend,max_discount,usage_limit,transferable,terms_text,supply_limit,
    all_branches,theme_override_code,theme_override_config,occasion_greeting,
    status,effective_from,created_by
  ) values (
    p_template_id,v_no,nullif(trim(coalesce(p_version_name,'')),''),p_face_value,p_discount_percent,
    v_anchor,v_mode,
    case when v_mode='days' then p_valid_days else null end,
    case when v_mode='months' then p_valid_months else null end,
    case when v_mode='fixed' then p_valid_until else null end,
    p_min_spend,p_max_discount,p_usage_limit,coalesce(p_transferable,true),
    nullif(trim(coalesce(p_terms_text,'')),''),p_supply_limit,coalesce(p_all_branches,false),
    nullif(trim(coalesce(p_theme_override_code,'')),''),coalesce(p_theme_override_config,'{}'::jsonb),
    nullif(trim(coalesce(p_occasion_greeting,'')),''),
    'active',now(),(select auth.uid())
  ) returning id into v_id;

  update public.voucher_templates
  set current_version_id=v_id,status='active',updated_at=now()
  where id=p_template_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
  values((select auth.uid()),'voucher_version_published','voucher_version',v_id::text,
    jsonb_build_object(
      'template_id',p_template_id,
      'version_no',v_no,
      'validity_anchor',v_anchor,
      'validity_mode',v_mode,
      'valid_days',case when v_mode='days' then p_valid_days else null end,
      'valid_months',case when v_mode='months' then p_valid_months else null end,
      'usage_limit',p_usage_limit,
      'theme_code',nullif(trim(coalesce(p_theme_override_code,'')),'')
    ));

  return v_id;
end;
$$;

revoke all on function public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text) from public, anon;
grant execute on function public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text) to authenticated;

-- Allocation v2 preserves legacy aggregation for issue-anchored Versions, but an
-- allocation-anchored Version creates a distinct batch every time Admin allocates.
-- Each batch therefore owns its own clock and cannot be silently reset by a later top-up.
create or replace function public.admin_engine_allocate_v2(
  p_partner_id uuid,
  p_version_id uuid,
  p_quantity integer,
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
  v_days integer;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
begin
  if p_partner_id is null or p_version_id is null then raise exception 'Partner and Version are required'; end if;
  if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be positive'; end if;

  if public.is_voucher_admin() then
    v_actor := (select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor := p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
  from public.admin_users a where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
    raise exception 'Active Partner not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));
  select vv.template_id,vv.validity_anchor,vv.valid_days
  into v_template_id,v_anchor,v_days
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active';
  if not found then raise exception 'Active Voucher Version not found'; end if;

  if v_anchor<>'allocation' then
    return public.admin_engine_allocate(p_partner_id,p_version_id,p_quantity,v_actor);
  end if;
  if v_days is null or v_days<1 then raise exception 'Allocation validity days are not configured'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_version_id::text,4301));
  v_valid_from := now();
  v_valid_until := now()+make_interval(days=>v_days);

  insert into public.partner_voucher_allocations(
    partner_id,version_id,quantity_allocated,quantity_revoked,status,
    valid_from,valid_until,created_by
  ) values (
    p_partner_id,p_version_id,p_quantity,0,'active',v_valid_from,v_valid_until,v_actor
  ) returning * into v_allocation;

  insert into public.partner_voucher_access(
    partner_id,template_id,status,quota_type,created_by,created_at,updated_at
  ) values (
    p_partner_id,v_template_id,'active','allocation',v_actor,now(),now()
  ) on conflict(partner_id,template_id) do update
    set status='active',quota_type='allocation',updated_at=now();

  insert into public.voucher_allocation_events(
    allocation_id,partner_id,version_id,event_type,quantity,actor_user_id
  ) values (v_allocation.id,p_partner_id,p_version_id,'allocated',p_quantity,v_actor);

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data
  ) values (
    v_actor,v_actor_name,'voucher_allocation_changed','voucher_allocation',v_allocation.id::text,p_partner_id,
    jsonb_build_object(
      'version_id',p_version_id,
      'quantity_added',p_quantity,
      'quantity_allocated',p_quantity,
      'validity_anchor','allocation',
      'valid_days',v_days,
      'valid_from',v_valid_from,
      'valid_until',v_valid_until,
      'created',true
    )
  );

  return jsonb_build_object(
    'success',true,
    'allocation_id',v_allocation.id,
    'partner_id',p_partner_id,
    'version_id',p_version_id,
    'quantity_added',p_quantity,
    'quantity_allocated',p_quantity,
    'quantity_revoked',0,
    'validity_anchor','allocation',
    'valid_from',v_valid_from,
    'valid_until',v_valid_until,
    'created',true
  );
end;
$$;

revoke all on function public.admin_engine_allocate_v2(uuid,uuid,integer,uuid) from public, anon;
grant execute on function public.admin_engine_allocate_v2(uuid,uuid,integer,uuid) to authenticated, service_role;

-- Canonical Partner issuance. Tenant still comes from Auth. For allocation-anchored
-- validity, issue from the earliest-expiring batch with remaining quantity.
create or replace function public.issue_engine_voucher(
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
  v_theme_code text;
  v_theme_config jsonb;
  v_snapshot jsonb;
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
  ) then raise exception 'This Partner is not authorised for this voucher type'; end if;

  select a.* into v_allocation
  from public.partner_voucher_allocations a
  where a.partner_id=v_partner_id
    and a.version_id=p_version_id
    and a.status='active'
    and (a.valid_from is null or a.valid_from<=now())
    and (a.valid_until is null or a.valid_until>=now())
    and (a.quantity_allocated-a.quantity_revoked) > (
      select count(*) from public.vouchers vx where vx.allocation_id=a.id
    )
  order by
    case when v_version.validity_anchor='allocation' then a.valid_until end asc nulls last,
    case when v_version.validity_anchor='allocation' then a.created_at end asc,
    a.created_at desc
  limit 1
  for update of a;
  if not found then raise exception 'No active allocation is available for this voucher type'; end if;

  select count(*) into v_issued from public.vouchers v where v.allocation_id=v_allocation.id;
  if v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued<=0 then
    raise exception 'Voucher allocation limit reached';
  end if;

  if v_version.supply_limit is not null then
    if (select count(*) from public.vouchers v where v.version_id=v_version.id) >= v_version.supply_limit then
      raise exception 'Voucher version supply limit reached';
    end if;
  end if;

  if v_version.validity_anchor='allocation' then
    if v_allocation.valid_until is null then raise exception 'Allocation expiry is not configured'; end if;
    v_expiry_date := (v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
    if v_expiry_date < v_issue_date then raise exception 'Voucher allocation has expired'; end if;
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

  select coalesce(s.all_branches,false) into v_partner_all_branches
  from public.partner_claim_settings s where s.partner_id=v_partner_id;
  if not found then v_partner_all_branches:=false; end if;
  v_final_all_branches:=v_partner_all_branches and v_version.all_branches;

  v_voucher_code:='EO-'||to_char(v_issue_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_voucher_type:=case
    when v_version.face_value is not null then 'RM'||trim(to_char(v_version.face_value,'FM999999990.##'))||' '||v_template.template_name
    when v_version.discount_percent is not null then trim(to_char(v_version.discount_percent,'FM999999990.##'))||'% '||v_template.template_name
    else v_template.template_name
  end;

  v_theme_code:=coalesce(nullif(v_version.theme_override_code,''),nullif(v_template.theme_code,''),'default');
  v_theme_config:=case
    when nullif(v_version.theme_override_code,'') is not null then coalesce(v_version.theme_override_config,'{}'::jsonb)
    else coalesce(v_template.theme_config,'{}'::jsonb)
  end;
  v_snapshot:=jsonb_build_object(
    'snapshot_version',1,
    'template_id',v_template.id,
    'template_code',v_template.template_code,
    'template_name',v_template.template_name,
    'version_id',v_version.id,
    'version_no',v_version.version_no,
    'version_name',v_version.version_name,
    'validity_anchor',v_version.validity_anchor,
    'validity_mode',v_version.validity_mode,
    'valid_days',v_version.valid_days,
    'valid_months',v_version.valid_months,
    'expiry_date',v_expiry_date,
    'theme_code',v_theme_code,
    'theme_config',v_theme_config,
    'share_intro','A little gift for you 🎁✨',
    'occasion_greeting',v_version.occasion_greeting,
    'terms_text',v_version.terms_text
  );

  insert into public.vouchers(
    voucher_code,partner_id,customer_name,customer_phone,voucher_type,status,expiry_date,
    issued_by_user_id,issued_by_name,all_branches,usage_limit,usage_count,
    template_id,version_id,allocation_id,metadata,presentation_snapshot
  ) values (
    v_voucher_code,v_partner_id,trim(p_customer_name),nullif(trim(coalesce(p_customer_phone,'')),''),v_voucher_type,'active',v_expiry_date,
    v_uid,coalesce(nullif(trim(coalesce(v_staff_name,'')),''),case when v_partner_role='partner_admin' then 'Partner Admin' else 'Partner Staff' end),
    v_final_all_branches,v_version.usage_limit,0,
    v_template.id,v_version.id,v_allocation.id,
    jsonb_build_object('issuance_path','engine_v2','template_code',v_template.template_code,'version_no',v_version.version_no,'theme_code',v_theme_code),
    v_snapshot
  ) returning id,public_token into v_voucher_id,v_public_token;

  -- Materialise the exact branch set for every new Voucher, including "all branches".
  -- This makes the issued branch scope historical instead of a live pointer to future Partner settings.
  if v_partner_all_branches and v_version.all_branches then
    insert into public.voucher_branches(voucher_id,branch_id)
    select v_voucher_id,b.id from public.branches b where b.status='active';
  elsif not v_partner_all_branches and v_version.all_branches then
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

  select count(*) into v_branch_count from public.voucher_branches vb where vb.voucher_id=v_voucher_id;
  if v_branch_count=0 then raise exception 'No valid redemption branch is shared by Partner and Voucher Version'; end if;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,coalesce(v_staff_name,v_partner_role),'engine_voucher_issued','voucher',v_voucher_id::text,v_partner_id,
    jsonb_build_object(
      'voucher_code',v_voucher_code,
      'template_code',v_template.template_code,
      'version_no',v_version.version_no,
      'validity_anchor',v_version.validity_anchor,
      'expiry_date',v_expiry_date,
      'branch_snapshot_count',v_branch_count,
      'theme_code',v_theme_code
    ),
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
    'validity_anchor',v_version.validity_anchor,
    'all_branches',v_final_all_branches,
    'branch_snapshot_count',v_branch_count,
    'usage_limit',v_version.usage_limit,
    'remaining_after_issue',greatest(0,v_allocation.quantity_allocated-v_allocation.quantity_revoked-v_issued-1),
    'theme_code',v_theme_code,
    'theme_config',v_theme_config,
    'share_intro','A little gift for you 🎁✨',
    'occasion_greeting',v_version.occasion_greeting
  );
end;
$$;

revoke all on function public.issue_engine_voucher(uuid,text,text) from public, anon;
grant execute on function public.issue_engine_voucher(uuid,text,text) to authenticated;

-- Redemption uses materialised voucher_branches whenever present. Legacy all_branches
-- vouchers with no snapshot rows keep the prior compatibility behaviour.
create or replace function public.redeem_voucher(
  p_voucher_code text,
  p_notes text default null,
  p_branch_code text default null,
  p_redeem_method text default 'qr'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_voucher public.vouchers%rowtype;
  v_branch_id uuid;
  v_branch_name text;
  v_allowed boolean := false;
  v_has_branch_snapshot boolean := false;
  v_new_usage integer;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_redemption_id uuid;
  v_method text;
begin
  if v_uid is null then return jsonb_build_object('success',false,'error','Authentication required'); end if;
  v_method:=lower(trim(coalesce(p_redeem_method,'qr')));
  if v_method not in ('qr','manual_code','admin') then return jsonb_build_object('success',false,'error','Invalid redeem method'); end if;

  select * into v_staff from public.staff_users su
  where su.user_id=v_uid and su.status='active' limit 1;
  if not found then return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended'); end if;

  if v_staff.role='all_branch_manager' then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where upper(b.branch_code)=upper(trim(p_branch_code)) and b.status='active' limit 1;
  else
    if v_staff.branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where b.id=v_staff.branch_id and b.status='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;

  select * into v_voucher from public.vouchers v
  where upper(v.voucher_code)=upper(trim(p_voucher_code)) for update;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;

  if v_voucher.status='revoked' then return jsonb_build_object('success',false,'error','Voucher has been revoked','status',v_voucher.status); end if;
  if v_voucher.status='expired' or v_voucher.expiry_date<v_today then
    update public.vouchers set status=case when status='active' then 'expired' else status end,updated_at=v_now where id=v_voucher.id;
    return jsonb_build_object('success',false,'error','Voucher has expired','status','expired');
  end if;
  if v_voucher.status='redeemed' or v_voucher.usage_count>=v_voucher.usage_limit then
    return jsonb_build_object('success',false,'error','Voucher has already been fully redeemed','status','redeemed');
  end if;
  if v_voucher.status<>'active' then return jsonb_build_object('success',false,'error','Voucher is not active','status',v_voucher.status); end if;

  select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id) into v_has_branch_snapshot;
  if v_has_branch_snapshot then
    select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  elsif v_voucher.all_branches then
    v_allowed:=true;
  else
    v_allowed:=false;
  end if;
  if not v_allowed then return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch'); end if;

  v_new_usage:=v_voucher.usage_count+1;
  insert into public.redemptions(voucher_id,partner_id,branch_id,staff_user_id,staff_name_snapshot,redeem_method,status,redeemed_at,notes)
  values(v_voucher.id,v_voucher.partner_id,v_branch_id,v_uid,v_staff.staff_name,v_method,'completed',v_now,nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_redemption_id;

  update public.vouchers set usage_count=v_new_usage,status=case when v_new_usage>=usage_limit then 'redeemed' else 'active' end,updated_at=v_now where id=v_voucher.id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(v_uid,v_staff.staff_name,'voucher_redeemed','redemption',v_redemption_id::text,v_voucher.partner_id,
    jsonb_build_object('voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'branch_id',v_branch_id,'branch_name',v_branch_name,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit),
    jsonb_build_object('redeem_method',v_method,'branch_scope_source',case when v_has_branch_snapshot then 'voucher_snapshot' else 'legacy_all_branches' end));

  return jsonb_build_object('success',true,'redemption_id',v_redemption_id,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,
    'customer_name',v_voucher.customer_name,'voucher_type',v_voucher.voucher_type,'branch_id',v_branch_id,'branch_name',v_branch_name,
    'staff_name',v_staff.staff_name,'redeemed_at',v_now,'usage_count',v_new_usage,'usage_limit',v_voucher.usage_limit,
    'remaining_uses',greatest(0,v_voucher.usage_limit-v_new_usage),'status',case when v_new_usage>=v_voucher.usage_limit then 'redeemed' else 'active' end);
end;
$$;

revoke all on function public.redeem_voucher(text,text,text,text) from public, anon;
grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;

-- Public customer view now reads issued presentation_snapshot first. Version/Template
-- joins are fallback only for pre-snapshot legacy rows.
create or replace function public.get_public_voucher(p_token uuid)
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
    'success',true,
    'voucher_code',v.voucher_code,
    'voucher_type',v.voucher_type,
    'customer_name',v.customer_name,
    'partner_name',p.partner_name,
    'expiry_date',v.expiry_date,
    'status',case
      when v.status='redeemed' then 'redeemed'
      when v.status='revoked' then 'revoked'
      when v.status='expired' then 'expired'
      when v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
      when v.status='active' then 'valid'
      else v.status end,
    'canonical_status',v.status,
    'issued_at',v.issued_at,
    'all_branches',v.all_branches,
    'theme_code',coalesce(v.presentation_snapshot->>'theme_code',vv.theme_override_code,vt.theme_code,'default'),
    'theme_config',coalesce(v.presentation_snapshot->'theme_config',case when vv.theme_override_code is not null then vv.theme_override_config else vt.theme_config end,'{}'::jsonb),
    'share_intro',coalesce(v.presentation_snapshot->>'share_intro','A little gift for you 🎁✨'),
    'occasion_greeting',coalesce(v.presentation_snapshot->>'occasion_greeting',vv.occasion_greeting),
    'terms_text',coalesce(v.presentation_snapshot->>'terms_text',vv.terms_text),
    'validity_anchor',coalesce(v.presentation_snapshot->>'validity_anchor',vv.validity_anchor,'issue'),
    'branches',coalesce(
      (select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
       from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
       where vb.voucher_id=v.id and b.status='active'),
      case when v.all_branches then
        (select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
         from public.branches b where b.status='active')
      else '[]'::jsonb end,
      '[]'::jsonb
    )
  ) into v_result
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  left join public.voucher_versions vv on vv.id=v.version_id
  left join public.voucher_templates vt on vt.id=v.template_id
  where v.public_token=p_token
  limit 1;

  if v_result is null then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  return v_result;
end;
$$;

revoke all on function public.get_public_voucher(uuid) from public;
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;

-- Canonical Partner/Admin share payload. It uses the issued Voucher snapshot and the
-- materialised branch set; the browser only appends the customer voucher URL.
create or replace function public.get_partner_voucher_share(p_voucher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id uuid;
  v_voucher_code text;
  v_voucher_type text;
  v_expiry date;
  v_snapshot jsonb;
  v_intro text;
  v_occasion text;
  v_branches jsonb;
  v_branch_text text;
  v_message text;
begin
  select v.partner_id,v.voucher_code,v.voucher_type,v.expiry_date,v.presentation_snapshot
  into v_partner_id,v_voucher_code,v_voucher_type,v_expiry,v_snapshot
  from public.vouchers v where v.id=p_voucher_id;
  if not found then raise exception 'Voucher not found'; end if;

  if not public.is_voucher_admin() and public.current_partner_id() is distinct from v_partner_id then
    raise exception 'Voucher access denied';
  end if;

  v_intro:=coalesce(nullif(v_snapshot->>'share_intro',''),'A little gift for you 🎁✨');
  v_occasion:=nullif(v_snapshot->>'occasion_greeting','');

  select coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
         coalesce(string_agg(
           'Evolution Optical – '||b.branch_name||E'\n'||
           coalesce(b.address,'')||
           case when nullif(b.phone,'') is not null then E'\n'||b.phone else '' end,
           E'\n\n' order by b.branch_name
         ),'')
  into v_branches,v_branch_text
  from public.voucher_branches vb
  join public.branches b on b.id=vb.branch_id
  where vb.voucher_id=p_voucher_id and b.status='active';

  v_message := 'Hi 👋'||E'\n'||v_intro||E'\n'||
    case when v_occasion is not null then v_occasion||E'\n' else '' end||
    'Here is your Evolution Optical Voucher.'||E'\n\n'||
    'Voucher: '||v_voucher_type||E'\n'||
    'Valid until: '||to_char(v_expiry,'DD Mon YYYY')||E'\n\n'||
    'Redeem at:'||E'\n'||v_branch_text;

  return jsonb_build_object(
    'success',true,
    'voucher_id',p_voucher_id,
    'voucher_code',v_voucher_code,
    'voucher_type',v_voucher_type,
    'expiry_date',v_expiry,
    'share_intro',v_intro,
    'occasion_greeting',v_occasion,
    'branches',v_branches,
    'message_body',v_message
  );
end;
$$;

revoke all on function public.get_partner_voucher_share(uuid) from public, anon;
grant execute on function public.get_partner_voucher_share(uuid) to authenticated;

-- Freeze presentation for any pre-existing reconstructed rows so later design edits
-- cannot mutate their customer-facing appearance. New blank production targets will
-- normally have nothing to backfill here.
update public.vouchers v
set presentation_snapshot=jsonb_build_object(
  'snapshot_version',1,
  'template_id',v.template_id,
  'template_code',vt.template_code,
  'template_name',vt.template_name,
  'version_id',v.version_id,
  'version_no',vv.version_no,
  'version_name',vv.version_name,
  'validity_anchor',coalesce(vv.validity_anchor,'issue'),
  'validity_mode',vv.validity_mode,
  'valid_days',vv.valid_days,
  'valid_months',vv.valid_months,
  'expiry_date',v.expiry_date,
  'theme_code',coalesce(nullif(vv.theme_override_code,''),nullif(vt.theme_code,''),'default'),
  'theme_config',case when nullif(vv.theme_override_code,'') is not null then coalesce(vv.theme_override_config,'{}'::jsonb) else coalesce(vt.theme_config,'{}'::jsonb) end,
  'share_intro','A little gift for you 🎁✨',
  'occasion_greeting',vv.occasion_greeting,
  'terms_text',vv.terms_text
)
from public.voucher_versions vv
join public.voucher_templates vt on vt.id=vv.template_id
where v.version_id=vv.id
  and (v.presentation_snapshot='{}'::jsonb or v.presentation_snapshot is null);
