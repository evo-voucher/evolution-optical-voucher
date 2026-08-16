-- Canonical allocation-level branch scope.
-- Issued scope = Partner claim scope ∩ Version scope ∩ Allocation scope.
-- This migration owns the final Version publication and Allocation contracts.

alter table public.partner_voucher_allocations
  add column if not exists all_branches boolean not null default true;

create table if not exists public.partner_voucher_allocation_branches (
  allocation_id uuid not null references public.partner_voucher_allocations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key(allocation_id,branch_id)
);

create index if not exists idx_partner_voucher_allocation_branches_branch
  on public.partner_voucher_allocation_branches(branch_id);

alter table public.partner_voucher_allocation_branches enable row level security;
revoke all on public.partner_voucher_allocation_branches from anon, authenticated;
grant select on public.partner_voucher_allocation_branches to authenticated;

drop policy if exists partner_voucher_allocation_branches_read_scope on public.partner_voucher_allocation_branches;
create policy partner_voucher_allocation_branches_read_scope
on public.partner_voucher_allocation_branches for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.partner_voucher_allocations a
    where a.id=partner_voucher_allocation_branches.allocation_id
      and a.partner_id=public.current_partner_id()
  )
);

-- Final issued branch snapshot is filtered by Allocation scope without reopening issued rows.
create or replace function public.filter_voucher_branch_by_allocation_scope()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_allocation_id uuid;
  v_all_branches boolean;
begin
  select v.allocation_id into v_allocation_id
  from public.vouchers v where v.id=new.voucher_id;

  if v_allocation_id is null then return new; end if;

  select a.all_branches into v_all_branches
  from public.partner_voucher_allocations a where a.id=v_allocation_id;

  if coalesce(v_all_branches,true) then return new; end if;

  if exists(
    select 1 from public.partner_voucher_allocation_branches ab
    where ab.allocation_id=v_allocation_id and ab.branch_id=new.branch_id
  ) then return new; end if;

  return null;
end;
$$;

drop trigger if exists voucher_branches_filter_allocation_scope on public.voucher_branches;
create trigger voucher_branches_filter_allocation_scope
before insert on public.voucher_branches
for each row execute function public.filter_voucher_branch_by_allocation_scope();

-- One canonical Version publication API. No v2/v3/theme wrapper is required after this point.
create or replace function public.admin_publish_voucher_version(
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
  p_all_branches boolean default true,
  p_branch_codes text[] default null,
  p_theme_code text default null,
  p_theme_config jsonb default '{}'::jsonb,
  p_greeting_text text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_no integer;
  v_mode text;
  v_template_status text;
  v_requested integer;
  v_resolved integer;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select vt.status into v_template_status
  from public.voucher_templates vt
  where vt.id=p_template_id
  for update;
  if not found or v_template_status='archived' then
    raise exception 'Voucher template not found or archived';
  end if;

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

  if not coalesce(p_all_branches,true) then
    v_requested:=coalesce((
      select count(distinct upper(trim(x)))
      from unnest(coalesce(p_branch_codes,array[]::text[])) x
      where nullif(trim(x),'') is not null
    ),0);
    if v_requested<1 then raise exception 'Select at least one Version branch'; end if;

    select count(*) into v_resolved
    from public.branches b
    where b.status='active'
      and upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(coalesce(p_branch_codes,array[]::text[])) x
        where nullif(trim(x),'') is not null
      );
    if v_resolved<>v_requested then
      raise exception 'One or more Version branches are invalid or inactive';
    end if;
  end if;

  select coalesce(max(version_no),0)+1 into v_no
  from public.voucher_versions
  where template_id=p_template_id;

  insert into public.voucher_versions(
    template_id,version_no,version_name,face_value,discount_percent,validity_mode,
    valid_days,valid_months,valid_until,min_spend,max_discount,usage_limit,
    transferable,terms_text,supply_limit,all_branches,theme_override_code,
    theme_override_config,greeting_text,status,effective_from,created_by
  ) values (
    p_template_id,v_no,nullif(trim(coalesce(p_version_name,'')),''),p_face_value,p_discount_percent,v_mode,
    case when v_mode='days' then p_valid_days end,
    case when v_mode='months' then p_valid_months end,
    case when v_mode='fixed' then p_valid_until end,
    p_min_spend,p_max_discount,p_usage_limit,coalesce(p_transferable,true),
    nullif(trim(coalesce(p_terms_text,'')),''),p_supply_limit,coalesce(p_all_branches,true),
    nullif(trim(coalesce(p_theme_code,'')),''),coalesce(p_theme_config,'{}'::jsonb),
    nullif(trim(coalesce(p_greeting_text,'')),''),'active',now(),(select auth.uid())
  ) returning id into v_id;

  if not coalesce(p_all_branches,true) then
    insert into public.voucher_version_branches(version_id,branch_id)
    select v_id,b.id
    from public.branches b
    where b.status='active'
      and upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(p_branch_codes) x
        where nullif(trim(x),'') is not null
      )
    on conflict do nothing;
  end if;

  update public.voucher_templates
  set current_version_id=v_id,status='active',updated_at=now()
  where id=p_template_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
  values(
    (select auth.uid()),'voucher_version_published','voucher_version',v_id::text,
    jsonb_build_object(
      'template_id',p_template_id,
      'version_no',v_no,
      'validity_mode',v_mode,
      'valid_days',case when v_mode='days' then p_valid_days end,
      'valid_months',case when v_mode='months' then p_valid_months end,
      'all_branches',coalesce(p_all_branches,true),
      'branch_codes',coalesce(p_branch_codes,array[]::text[]),
      'theme_code',nullif(trim(coalesce(p_theme_code,'')),'')
    )
  );

  return v_id;
end;
$$;

revoke all on function public.admin_publish_voucher_version(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text[],text,jsonb,text) from public,anon;
grant execute on function public.admin_publish_voucher_version(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text[],text,jsonb,text) to authenticated;

-- One canonical scoped Allocation API. Trusted mutation is service-role only.
create or replace function public.admin_engine_allocate(
  p_partner_id uuid,
  p_version_id uuid,
  p_quantity integer,
  p_validity_anchor text default 'issue',
  p_allocation_valid_days integer default null,
  p_all_branches boolean default true,
  p_branch_codes text[] default null,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor uuid;
  v_actor_name text;
  v_template_id uuid;
  v_anchor text;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_requested integer;
  v_resolved integer;
begin
  if p_partner_id is null or p_version_id is null then raise exception 'Partner and Version are required'; end if;
  if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be positive'; end if;

  v_anchor:=case lower(trim(coalesce(p_validity_anchor,'')))
    when 'issue' then 'issue'
    when 'from_issue' then 'issue'
    when 'allocation' then 'allocation'
    when 'from_allocation' then 'allocation'
    else null end;
  if v_anchor is null then raise exception 'Unsupported validity anchor'; end if;
  if v_anchor='allocation' and (p_allocation_valid_days is null or p_allocation_valid_days<1) then
    raise exception 'Allocation validity days must be at least 1';
  end if;

  if public.is_voucher_admin() then
    v_actor:=(select auth.uid());
  elsif public.is_trusted_service_role() then
    v_actor:=p_actor_user_id;
  else
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
  from public.admin_users a
  where a.user_id=v_actor and a.status='active';
  if not found then raise exception 'Active Admin actor required'; end if;

  if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
    raise exception 'Active Partner not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));

  select vv.template_id into v_template_id
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id
  where vv.id=p_version_id and vv.status='active' and vt.status='active';
  if not found then raise exception 'Active Voucher Version not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_version_id::text,4401));

  if not coalesce(p_all_branches,true) then
    v_requested:=coalesce((
      select count(distinct upper(trim(x)))
      from unnest(coalesce(p_branch_codes,array[]::text[])) x
      where nullif(trim(x),'') is not null
    ),0);
    if v_requested<1 then raise exception 'Select at least one Allocation branch'; end if;

    select count(*) into v_resolved
    from public.branches b
    where b.status='active'
      and upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(coalesce(p_branch_codes,array[]::text[])) x
        where nullif(trim(x),'') is not null
      );
    if v_resolved<>v_requested then
      raise exception 'One or more Allocation branches are invalid or inactive';
    end if;
  end if;

  if v_anchor='allocation' then
    v_valid_from:=now();
    v_valid_until:=now()+make_interval(days=>p_allocation_valid_days);
  end if;

  insert into public.partner_voucher_allocations(
    partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,
    allocation_valid_days,valid_from,valid_until,all_branches,created_by
  ) values (
    p_partner_id,p_version_id,p_quantity,0,'active',v_anchor,
    case when v_anchor='allocation' then p_allocation_valid_days end,
    v_valid_from,v_valid_until,coalesce(p_all_branches,true),v_actor
  ) returning * into v_allocation;

  if not coalesce(p_all_branches,true) then
    insert into public.partner_voucher_allocation_branches(allocation_id,branch_id)
    select v_allocation.id,b.id
    from public.branches b
    where b.status='active'
      and upper(b.branch_code)=any(
        select upper(trim(x))
        from unnest(p_branch_codes) x
        where nullif(trim(x),'') is not null
      );
  end if;

  insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by,created_at,updated_at)
  values(p_partner_id,v_template_id,'active','allocation',v_actor,now(),now())
  on conflict(partner_id,template_id) do update
    set status='active',quota_type='allocation',updated_at=now();

  insert into public.voucher_allocation_events(allocation_id,partner_id,version_id,event_type,quantity,actor_user_id)
  values(v_allocation.id,p_partner_id,p_version_id,'allocated',p_quantity,v_actor);

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data)
  values(
    v_actor,v_actor_name,'voucher_allocation_changed','voucher_allocation',v_allocation.id::text,p_partner_id,
    jsonb_build_object(
      'version_id',p_version_id,
      'quantity_added',p_quantity,
      'quantity_allocated',p_quantity,
      'validity_anchor',v_anchor,
      'allocation_valid_days',case when v_anchor='allocation' then p_allocation_valid_days end,
      'all_branches',coalesce(p_all_branches,true),
      'branch_codes',coalesce(p_branch_codes,array[]::text[]),
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
    'validity_anchor',v_anchor,
    'allocation_valid_days',case when v_anchor='allocation' then p_allocation_valid_days end,
    'all_branches',coalesce(p_all_branches,true),
    'branch_codes',coalesce(p_branch_codes,array[]::text[]),
    'valid_from',v_valid_from,
    'valid_until',v_valid_until,
    'created',true
  );
end;
$$;

revoke all on function public.admin_engine_allocate(uuid,uuid,integer,text,integer,boolean,text[],uuid) from public,anon,authenticated;
grant execute on function public.admin_engine_allocate(uuid,uuid,integer,text,integer,boolean,text[],uuid) to service_role;

-- Retire superseded Version publication variants from the rebuild end state.
drop function if exists public.admin_publish_voucher_version_v3(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text[],text,jsonb,text);
drop function if exists public.admin_publish_voucher_version_v2(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text,jsonb,text);
drop function if exists public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text);

-- Retire superseded Allocation variants from the rebuild end state.
drop function if exists public.admin_engine_allocate_all(uuid,integer,uuid);
drop function if exists public.admin_engine_allocate_v2(uuid,uuid,integer,text,integer,uuid);
drop function if exists public.admin_engine_allocate_v3(uuid,uuid,integer,text,integer,boolean,text[],uuid);
drop function if exists public.admin_engine_allocate(uuid,uuid,integer,uuid);
