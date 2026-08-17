-- Canonical source recovery: converge the reproducible local rebuild with the
-- currently verified canonical runtime allocation contract.
--
-- Hosted production does not carry branch_scope_snapshotted, so this migration
-- intentionally remains a no-op on that lineage.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    alter table public.partner_voucher_allocations
      add column if not exists validity_value integer,
      add column if not exists validity_unit text;

    if not exists (
      select 1 from pg_constraint where conname='partner_voucher_allocations_validity_value_check'
        and conrelid='public.partner_voucher_allocations'::regclass
    ) then
      alter table public.partner_voucher_allocations
        add constraint partner_voucher_allocations_validity_value_check
        check (validity_value is null or validity_value>=1);
    end if;

    if not exists (
      select 1 from pg_constraint where conname='partner_voucher_allocations_validity_unit_check'
        and conrelid='public.partner_voucher_allocations'::regclass
    ) then
      alter table public.partner_voucher_allocations
        add constraint partner_voucher_allocations_validity_unit_check
        check (validity_unit is null or validity_unit in ('days','months'));
    end if;

    execute $sql$
      create or replace function public.admin_preview_allocation_effective_branches(
        p_partner_id uuid,
        p_version_id uuid,
        p_all_branches boolean default true,
        p_branch_codes text[] default null
      )
      returns table(branch_id uuid,branch_code text,branch_name text,address text,phone text)
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_partner_all boolean := false;
        v_version_all boolean := false;
        v_requested integer := 0;
        v_resolved integer := 0;
      begin
        if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
        if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
          raise exception 'Active Partner not found';
        end if;

        select vv.all_branches into v_version_all
        from public.voucher_versions vv
        join public.voucher_templates vt on vt.id=vv.template_id
        where vv.id=p_version_id and vv.status='active' and vt.status='active';
        if not found then raise exception 'Active Voucher Version not found'; end if;

        select coalesce(s.all_branches,false) into v_partner_all
        from public.partner_claim_settings s where s.partner_id=p_partner_id;
        if not found then v_partner_all:=false; end if;

        if not coalesce(p_all_branches,true) then
          v_requested:=coalesce((select count(distinct upper(trim(x)))
            from unnest(coalesce(p_branch_codes,array[]::text[])) x
            where nullif(trim(x),'') is not null),0);
          if v_requested<1 then raise exception 'Select at least one Allocation branch'; end if;
          select count(*) into v_resolved from public.branches b
          where b.status='active' and upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(coalesce(p_branch_codes,array[]::text[])) x
            where nullif(trim(x),'') is not null
          );
          if v_resolved<>v_requested then raise exception 'One or more Allocation branches are invalid or inactive'; end if;
        end if;

        return query
        select b.id,b.branch_code,b.branch_name,b.address,b.phone
        from public.branches b
        where b.status='active'
          and (v_partner_all or exists(
            select 1 from public.partner_claim_branches pcb
            where pcb.partner_id=p_partner_id and pcb.branch_id=b.id
          ))
          and (v_version_all or exists(
            select 1 from public.voucher_version_branches vvb
            where vvb.version_id=p_version_id and vvb.branch_id=b.id
          ))
          and (coalesce(p_all_branches,true) or upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(coalesce(p_branch_codes,array[]::text[])) x
            where nullif(trim(x),'') is not null
          ))
        order by b.branch_name,b.branch_code;
      end;
      $fn$;
    $sql$;

    execute $sql$
      create or replace function public.admin_engine_allocate(
        p_partner_id uuid,
        p_version_id uuid,
        p_quantity integer,
        p_validity_anchor text default 'issue',
        p_allocation_valid_days integer default null,
        p_all_branches boolean default true,
        p_branch_codes text[] default null,
        p_actor_user_id uuid default null,
        p_validity_value integer default null,
        p_validity_unit text default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare
        v_actor uuid;
        v_actor_name text;
        v_template_id uuid;
        v_anchor text;
        v_unit text;
        v_value integer;
        v_allocation public.partner_voucher_allocations%rowtype;
        v_valid_from timestamptz;
        v_valid_until timestamptz;
        v_requested integer;
        v_resolved integer;
      begin
        if p_partner_id is null or p_version_id is null then raise exception 'Partner and Version are required'; end if;
        if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be positive'; end if;

        v_anchor:=case lower(trim(coalesce(p_validity_anchor,'')))
          when 'issue' then 'issue' when 'from_issue' then 'issue'
          when 'allocation' then 'allocation' when 'from_allocation' then 'allocation'
          else null end;
        if v_anchor is null then raise exception 'Unsupported validity anchor'; end if;

        v_value:=coalesce(p_validity_value,case when p_allocation_valid_days is not null then p_allocation_valid_days else null end);
        v_unit:=lower(trim(coalesce(p_validity_unit,case when p_allocation_valid_days is not null then 'days' else '' end)));
        if v_value is null or v_value<1 then raise exception 'Validity value must be at least 1'; end if;
        if v_unit not in ('days','months') then raise exception 'Validity unit must be days or months'; end if;

        if public.is_voucher_admin() then v_actor:=(select auth.uid());
        elsif public.is_trusted_service_role() then v_actor:=p_actor_user_id;
        else raise exception 'Admin access required'; end if;

        select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name
        from public.admin_users a where a.user_id=v_actor and a.status='active';
        if not found then raise exception 'Active Admin actor required'; end if;
        if not exists(select 1 from public.partners p where p.id=p_partner_id and p.status='active') then
          raise exception 'Active Partner not found';
        end if;

        perform pg_advisory_xact_lock(hashtextextended(p_version_id::text,2601));
        select vv.template_id into v_template_id
        from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id
        where vv.id=p_version_id and vv.status='active' and vt.status='active';
        if not found then raise exception 'Active Voucher Version not found'; end if;
        perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_version_id::text,4401));

        if not coalesce(p_all_branches,true) then
          v_requested:=coalesce((select count(distinct upper(trim(x)))
            from unnest(coalesce(p_branch_codes,array[]::text[])) x where nullif(trim(x),'') is not null),0);
          if v_requested<1 then raise exception 'Select at least one Allocation branch'; end if;
          select count(*) into v_resolved from public.branches b
          where b.status='active' and upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(coalesce(p_branch_codes,array[]::text[])) x where nullif(trim(x),'') is not null
          );
          if v_resolved<>v_requested then raise exception 'One or more Allocation branches are invalid or inactive'; end if;
        end if;

        if v_anchor='allocation' then
          v_valid_from:=now();
          v_valid_until:=case v_unit
            when 'days' then now()+make_interval(days=>v_value)
            when 'months' then now()+make_interval(months=>v_value)
          end;
        end if;

        insert into public.partner_voucher_allocations(
          partner_id,version_id,quantity_allocated,quantity_revoked,status,validity_anchor,
          allocation_valid_days,validity_value,validity_unit,valid_from,valid_until,all_branches,created_by
        ) values (
          p_partner_id,p_version_id,p_quantity,0,'active',v_anchor,
          case when v_anchor='allocation' and v_unit='days' then v_value end,
          v_value,v_unit,v_valid_from,v_valid_until,coalesce(p_all_branches,true),v_actor
        ) returning * into v_allocation;

        if not coalesce(p_all_branches,true) then
          insert into public.partner_voucher_allocation_branches(allocation_id,branch_id)
          select v_allocation.id,b.id from public.branches b
          where b.status='active' and upper(b.branch_code)=any(
            select upper(trim(x)) from unnest(p_branch_codes) x where nullif(trim(x),'') is not null
          );
        end if;

        insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by,created_at,updated_at)
        values(p_partner_id,v_template_id,'active','allocation',v_actor,now(),now())
        on conflict(partner_id,template_id) do update set status='active',quota_type='allocation',updated_at=now();

        insert into public.voucher_allocation_events(allocation_id,partner_id,version_id,event_type,quantity,actor_user_id)
        values(v_allocation.id,p_partner_id,p_version_id,'allocated',p_quantity,v_actor);

        insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data)
        values(v_actor,v_actor_name,'voucher_allocation_changed','voucher_allocation',v_allocation.id::text,p_partner_id,
          jsonb_build_object('version_id',p_version_id,'quantity_added',p_quantity,'quantity_allocated',p_quantity,
            'validity_anchor',v_anchor,'validity_value',v_value,'validity_unit',v_unit,
            'all_branches',coalesce(p_all_branches,true),'branch_codes',coalesce(p_branch_codes,array[]::text[]),
            'valid_from',v_valid_from,'valid_until',v_valid_until,'created',true));

        return jsonb_build_object('success',true,'allocation_id',v_allocation.id,'partner_id',p_partner_id,
          'version_id',p_version_id,'quantity_added',p_quantity,'quantity_allocated',p_quantity,
          'quantity_revoked',0,'validity_anchor',v_anchor,'validity_value',v_value,'validity_unit',v_unit,
          'all_branches',coalesce(p_all_branches,true),'branch_codes',coalesce(p_branch_codes,array[]::text[]),
          'valid_from',v_valid_from,'valid_until',v_valid_until,'created',true);
      end;
      $fn$;
    $sql$;

    revoke all on function public.admin_preview_allocation_effective_branches(uuid,uuid,boolean,text[]) from public,anon;
    grant execute on function public.admin_preview_allocation_effective_branches(uuid,uuid,boolean,text[]) to authenticated;
    revoke all on function public.admin_engine_allocate(uuid,uuid,integer,text,integer,boolean,text[],uuid,integer,text) from public,anon;
    grant execute on function public.admin_engine_allocate(uuid,uuid,integer,text,integer,boolean,text[],uuid,integer,text) to authenticated,service_role;
  end if;
end;
$migration$;
