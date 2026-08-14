-- Voucher Engine admin RPCs reconstructed from the validated legacy Voucher Engine UI.
-- Canonical validity modes remain fixed/days/months internally.

create or replace function public.admin_create_voucher_template_theme(
  p_template_code text,
  p_template_name text,
  p_voucher_category text,
  p_description text default null,
  p_theme_code text default 'classic'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if nullif(trim(coalesce(p_template_code,'')),'') is null then raise exception 'Template code is required'; end if;
  if nullif(trim(coalesce(p_template_name,'')),'') is null then raise exception 'Template name is required'; end if;

  insert into public.voucher_templates(
    template_code,template_name,voucher_category,description,status,theme_code,created_by
  ) values (
    upper(trim(p_template_code)),trim(p_template_name),lower(trim(coalesce(p_voucher_category,'custom'))),
    nullif(trim(coalesce(p_description,'')),''),'active',coalesce(nullif(trim(p_theme_code),''),'classic'),(select auth.uid())
  ) returning id into v_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
  values((select auth.uid()),'voucher_template_created','voucher_template',v_id::text,
    jsonb_build_object('template_code',upper(trim(p_template_code)),'template_name',trim(p_template_name),'theme_code',coalesce(nullif(trim(p_theme_code),''),'classic')));

  return v_id;
end;
$$;
revoke all on function public.admin_create_voucher_template_theme(text,text,text,text,text) from public, anon;
grant execute on function public.admin_create_voucher_template_theme(text,text,text,text,text) to authenticated;

create or replace function public.admin_publish_voucher_version_theme(
  p_template_id uuid,
  p_version_name text default null,
  p_face_value numeric default null,
  p_discount_percent numeric default null,
  p_validity_mode text default 'days_after_issue',
  p_valid_days integer default null,
  p_valid_months integer default null,
  p_min_spend numeric default null,
  p_max_discount numeric default null,
  p_usage_limit integer default 1,
  p_transferable boolean default true,
  p_terms_text text default null,
  p_supply_limit integer default null,
  p_all_branches boolean default false,
  p_theme_override_code text default null
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
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if not exists(select 1 from public.voucher_templates where id=p_template_id and status<>'archived') then
    raise exception 'Voucher template not found or archived';
  end if;

  v_mode := case lower(trim(coalesce(p_validity_mode,'')))
    when 'days_after_issue' then 'days'
    when 'calendar_months_after_issue' then 'months'
    when 'days' then 'days'
    when 'months' then 'months'
    when 'fixed' then 'fixed'
    else null end;

  if v_mode is null then raise exception 'Unsupported validity mode'; end if;
  if v_mode='days' and (p_valid_days is null or p_valid_days<1) then raise exception 'Valid days must be at least 1'; end if;
  if v_mode='months' and (p_valid_months is null or p_valid_months<1) then raise exception 'Valid months must be at least 1'; end if;
  if p_usage_limit is null or p_usage_limit<1 then raise exception 'Usage limit must be at least 1'; end if;

  select coalesce(max(version_no),0)+1 into v_no
  from public.voucher_versions where template_id=p_template_id;

  insert into public.voucher_versions(
    template_id,version_no,version_name,face_value,discount_percent,validity_mode,
    valid_days,valid_months,min_spend,max_discount,usage_limit,transferable,terms_text,
    supply_limit,all_branches,theme_override_code,status,effective_from,created_by
  ) values (
    p_template_id,v_no,nullif(trim(coalesce(p_version_name,'')),''),p_face_value,p_discount_percent,v_mode,
    case when v_mode='days' then p_valid_days else null end,
    case when v_mode='months' then p_valid_months else null end,
    p_min_spend,p_max_discount,p_usage_limit,coalesce(p_transferable,true),nullif(trim(coalesce(p_terms_text,'')),''),
    p_supply_limit,coalesce(p_all_branches,false),nullif(trim(coalesce(p_theme_override_code,'')),''),'active',now(),(select auth.uid())
  ) returning id into v_id;

  update public.voucher_templates
  set current_version_id=v_id,status='active',updated_at=now()
  where id=p_template_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
  values((select auth.uid()),'voucher_version_published','voucher_version',v_id::text,
    jsonb_build_object('template_id',p_template_id,'version_no',v_no,'validity_mode',v_mode,'usage_limit',p_usage_limit));

  return v_id;
end;
$$;
revoke all on function public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text) from public, anon;
grant execute on function public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text) to authenticated;
