-- Canonical source recovery for the live initial-Partner multi-allocation contract.
-- No-op on hosted production lineage.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.admin_provision_partner_with_initial_allocations(
        p_partner_code text,
        p_partner_name text,
        p_contact_person text,
        p_contact_phone text,
        p_staff_limit integer,
        p_new_user_id uuid,
        p_login_email text,
        p_actor_user_id uuid,
        p_allocations jsonb,
        p_all_branches boolean default false,
        p_branch_codes text[] default '{}'::text[]
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare
        v_actor_name text;
        v_partner public.partners%rowtype;
        v_partner_user public.partner_users%rowtype;
        v_requested integer := 0;
        v_resolved integer := 0;
        v_item jsonb;
        v_version_id uuid;
        v_quantity integer;
        v_anchor text;
        v_value integer;
        v_unit text;
        v_seen uuid[] := array[]::uuid[];
        v_results jsonb := '[]'::jsonb;
        v_allocation jsonb;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null or not exists(select 1 from public.admin_users a where a.user_id=p_actor_user_id and a.status='active') then raise exception 'Active Admin actor required'; end if;
        select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name from public.admin_users a where a.user_id=p_actor_user_id and a.status='active';
        if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then raise exception 'Valid Auth user is required'; end if;
        if nullif(trim(coalesce(p_partner_code,'')),'') is null or upper(trim(p_partner_code)) !~ '^[A-Z0-9_-]+$' then raise exception 'Invalid partner code'; end if;
        if nullif(trim(coalesce(p_partner_name,'')),'') is null then raise exception 'Partner name is required'; end if;
        if p_staff_limit is null or p_staff_limit<0 or p_staff_limit>1000 then raise exception 'Staff limit must be 0 to 1000'; end if;
        if nullif(trim(coalesce(p_login_email,'')),'') is null then raise exception 'Login email is required'; end if;
        if p_allocations is null or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)<1 then raise exception 'Select at least one initial Voucher'; end if;

        if not coalesce(p_all_branches,false) then
          v_requested:=coalesce((select count(distinct upper(trim(x))) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null),0);
          if v_requested<1 then raise exception 'Select at least one active claim branch'; end if;
          select count(*) into v_resolved from public.branches b
          where b.status='active' and upper(b.branch_code)=any(select upper(trim(x)) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null);
          if v_resolved<>v_requested then raise exception 'One or more claim branches are invalid or inactive'; end if;
        end if;

        for v_item in select value from jsonb_array_elements(p_allocations)
        loop
          begin v_version_id := nullif(v_item->>'version_id','')::uuid; exception when others then raise exception 'Invalid Voucher Version in initial allocations'; end;
          begin v_quantity := (v_item->>'quantity')::integer; exception when others then raise exception 'Initial allocation quantity must be a whole number'; end;
          v_anchor := lower(trim(coalesce(v_item->>'validity_anchor','issue')));
          begin v_value := (v_item->>'validity_value')::integer; exception when others then raise exception 'Validity value must be a whole number'; end;
          v_unit := lower(trim(coalesce(v_item->>'validity_unit','')));
          if v_version_id is null then raise exception 'Initial Voucher Version is required'; end if;
          if v_quantity is null or v_quantity<1 then raise exception 'Initial allocation quantity must be at least 1'; end if;
          if v_anchor not in ('issue','allocation') then raise exception 'Validity start must be issue or allocation'; end if;
          if v_value is null or v_value<1 then raise exception 'Validity value must be at least 1'; end if;
          if v_unit not in ('days','months') then raise exception 'Validity unit must be days or months'; end if;
          if v_version_id=any(v_seen) then raise exception 'Duplicate Voucher Version in initial allocations'; end if;
          v_seen := array_append(v_seen,v_version_id);
          if not exists(select 1 from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id where vv.id=v_version_id and vv.status='active' and vt.status='active') then raise exception 'Active Voucher Version not found'; end if;
        end loop;

        insert into public.partners(partner_code,partner_name,contact_person,contact_phone,voucher_limit,vouchers_issued,staff_limit,staff_access_enabled,status)
        values(upper(trim(p_partner_code)),trim(p_partner_name),nullif(trim(coalesce(p_contact_person,'')),''),nullif(trim(coalesce(p_contact_phone,'')),''),0,0,p_staff_limit,false,'active')
        returning * into v_partner;

        insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
        values(p_new_user_id,v_partner.id,'partner_admin','active',coalesce(nullif(trim(coalesce(p_contact_person,'')),''),trim(p_partner_name)),lower(trim(p_login_email)))
        returning * into v_partner_user;

        insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
        values(v_partner.id,coalesce(p_all_branches,false),p_actor_user_id);

        if not coalesce(p_all_branches,false) then
          insert into public.partner_claim_branches(partner_id,branch_id)
          select v_partner.id,b.id from public.branches b
          where b.status='active' and upper(b.branch_code)=any(select upper(trim(x)) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null);
        end if;

        for v_item in select value from jsonb_array_elements(p_allocations)
        loop
          v_version_id := (v_item->>'version_id')::uuid;
          v_quantity := (v_item->>'quantity')::integer;
          v_anchor := lower(trim(v_item->>'validity_anchor'));
          v_value := (v_item->>'validity_value')::integer;
          v_unit := lower(trim(v_item->>'validity_unit'));
          v_allocation := public.admin_engine_allocate(
            p_partner_id=>v_partner.id,
            p_version_id=>v_version_id,
            p_quantity=>v_quantity,
            p_validity_anchor=>v_anchor,
            p_allocation_valid_days=>null,
            p_all_branches=>coalesce(p_all_branches,false),
            p_branch_codes=>coalesce(p_branch_codes,'{}'::text[]),
            p_actor_user_id=>p_actor_user_id,
            p_validity_value=>v_value,
            p_validity_unit=>v_unit
          );
          v_results := v_results || jsonb_build_array(v_allocation);
        end loop;

        insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
        values(p_actor_user_id,v_actor_name,'partner_created','partner',v_partner.id::text,v_partner.id,
          jsonb_build_object('partner_code',v_partner.partner_code,'partner_name',v_partner.partner_name,'staff_limit',v_partner.staff_limit,'status',v_partner.status,'initial_allocations',p_allocations,'all_branches',coalesce(p_all_branches,false),'branch_codes',coalesce(p_branch_codes,'{}'::text[])),
          jsonb_build_object('login_email',lower(trim(p_login_email)),'secret_material_logged',false,'provisioning','atomic_multi_initial_setup_per_lot_validity','voucher_limit_retired',true));

        return jsonb_build_object('success',true,'partner',to_jsonb(v_partner),'partner_user_id',v_partner_user.id,'user_id',p_new_user_id,'initial_allocations',v_results,'claim_all_branches',coalesce(p_all_branches,false),'claim_branch_codes',coalesce(p_branch_codes,'{}'::text[]));
      end;
      $fn$;
    $sql$;

    revoke all on function public.admin_provision_partner_with_initial_allocations(text,text,text,text,integer,uuid,text,uuid,jsonb,boolean,text[]) from public,anon,authenticated;
    grant execute on function public.admin_provision_partner_with_initial_allocations(text,text,text,text,integer,uuid,text,uuid,jsonb,boolean,text[]) to service_role;
  end if;
end;
$migration$;
