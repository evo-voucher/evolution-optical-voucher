-- Canonical source recovery for the verified UAT Version publish RPC.
-- No-op on hosted production lineage.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
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
      as $fn$
      declare
        v_id uuid;
        v_no integer;
        v_mode text;
        v_template_status text;
        v_requested integer;
        v_resolved integer;
      begin
        if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
        select vt.status into v_template_status from public.voucher_templates vt where vt.id=p_template_id for update;
        if not found or v_template_status='archived' then raise exception 'Voucher template not found or archived'; end if;

        v_mode:=case lower(trim(coalesce(p_validity_mode,'')))
          when 'days_after_issue' then 'days' when 'days' then 'days'
          when 'calendar_months_after_issue' then 'months' when 'months' then 'months'
          when 'fixed' then 'fixed' else null end;
        if v_mode is null then raise exception 'Unsupported validity mode'; end if;
        if v_mode='days' and (p_valid_days is null or p_valid_days<1) then raise exception 'Valid days must be at least 1'; end if;
        if v_mode='months' and (p_valid_months is null or p_valid_months<1) then raise exception 'Valid months must be at least 1'; end if;
        if v_mode='fixed' and p_valid_until is null then raise exception 'Fixed validity requires valid_until'; end if;
        if p_usage_limit is null or p_usage_limit<1 then raise exception 'Usage limit must be at least 1'; end if;

        if not coalesce(p_all_branches,true) then
          v_requested:=coalesce((select count(distinct upper(trim(x))) from unnest(coalesce(p_branch_codes,array[]::text[])) x where nullif(trim(x),'') is not null),0);
          if v_requested<1 then raise exception 'Select at least one Version branch'; end if;
          select count(*) into v_resolved from public.branches b
          where b.status='active' and upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(coalesce(p_branch_codes,array[]::text[])) x where nullif(trim(x),'') is not null
          );
          if v_resolved<>v_requested then raise exception 'One or more Version branches are invalid or inactive'; end if;
        end if;

        select coalesce(max(version_no),0)+1 into v_no from public.voucher_versions where template_id=p_template_id;
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
          select v_id,b.id from public.branches b
          where b.status='active' and upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(p_branch_codes) x where nullif(trim(x),'') is not null
          ) on conflict do nothing;
        end if;

        update public.voucher_templates set current_version_id=v_id,status='active',updated_at=now() where id=p_template_id;
        insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,after_data)
        values((select auth.uid()),'voucher_version_published','voucher_version',v_id::text,
          jsonb_build_object('template_id',p_template_id,'version_no',v_no,'validity_mode',v_mode,
            'valid_days',case when v_mode='days' then p_valid_days end,
            'valid_months',case when v_mode='months' then p_valid_months end,
            'all_branches',coalesce(p_all_branches,true),'branch_codes',coalesce(p_branch_codes,array[]::text[]),
            'theme_code',nullif(trim(coalesce(p_theme_code,'')),'')));
        return v_id;
      end;
      $fn$;
    $sql$;

    revoke all on function public.admin_publish_voucher_version(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text[],text,jsonb,text) from public,anon;
    grant execute on function public.admin_publish_voucher_version(uuid,text,numeric,numeric,text,integer,integer,date,numeric,numeric,integer,boolean,text,integer,boolean,text[],text,jsonb,text) to authenticated;
  end if;
end;
$migration$;
