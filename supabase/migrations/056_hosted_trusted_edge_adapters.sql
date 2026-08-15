-- Hosted trusted Edge adapters.
-- Purpose: let one GitHub Edge Function source operate against both:
--   * fresh canonical schema, where canonical admin_* RPCs already exist; and
--   * existing hosted production, where proven svc_admin_* functions are the
--     authoritative mutation core.
--
-- This migration executes only on hosted lineage (canonical markers absent).
-- All adapter mutation functions remain service_role-only.

do $migration$
begin
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.admin_engine_allocate(
        p_partner_id uuid,
        p_version_id uuid,
        p_quantity integer,
        p_actor_user_id uuid default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare v_allocation_id uuid;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null then raise exception 'Admin actor is required'; end if;
        v_allocation_id:=public.svc_admin_allocate_voucher_to_partner(
          p_actor_user_id,p_partner_id,p_version_id,p_quantity,null,null
        );
        return jsonb_build_object(
          'success',true,
          'allocation_id',v_allocation_id,
          'partner_id',p_partner_id,
          'version_id',p_version_id,
          'quantity_added',p_quantity
        );
      end;
      $fn$;
      revoke all on function public.admin_engine_allocate(uuid,uuid,integer,uuid) from public,anon,authenticated;
      grant execute on function public.admin_engine_allocate(uuid,uuid,integer,uuid) to service_role;

      create or replace function public.admin_engine_allocate_all(
        p_version_id uuid,
        p_quantity integer,
        p_actor_user_id uuid default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare v_result jsonb;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null then raise exception 'Admin actor is required'; end if;
        v_result:=public.svc_admin_allocate_voucher_to_all_partners(
          p_actor_user_id,p_version_id,p_quantity,null,null
        );
        return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('success',true);
      end;
      $fn$;
      revoke all on function public.admin_engine_allocate_all(uuid,integer,uuid) from public,anon,authenticated;
      grant execute on function public.admin_engine_allocate_all(uuid,integer,uuid) to service_role;

      create or replace function public.admin_engine_revoke_unissued(
        p_allocation_id uuid,
        p_quantity integer,
        p_reason text default null,
        p_actor_user_id uuid default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare v_result jsonb;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null then raise exception 'Admin actor is required'; end if;
        v_result:=public.svc_admin_revoke_unissued_allocation(
          p_actor_user_id,p_allocation_id,p_quantity,p_reason
        );
        return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('success',true);
      end;
      $fn$;
      revoke all on function public.admin_engine_revoke_unissued(uuid,integer,text,uuid) from public,anon,authenticated;
      grant execute on function public.admin_engine_revoke_unissued(uuid,integer,text,uuid) to service_role;

      create or replace function public.admin_engine_retire_version(
        p_version_id uuid,
        p_reason text default null,
        p_actor_user_id uuid default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null then raise exception 'Admin actor is required'; end if;
        perform public.svc_admin_retire_voucher_version(p_actor_user_id,p_version_id,p_reason);
        return jsonb_build_object('success',true,'version_id',p_version_id,'status','retired');
      end;
      $fn$;
      revoke all on function public.admin_engine_retire_version(uuid,text,uuid) from public,anon,authenticated;
      grant execute on function public.admin_engine_retire_version(uuid,text,uuid) to service_role;

      create or replace function public.admin_provision_staff(
        p_new_user_id uuid,
        p_staff_name text,
        p_branch_id uuid,
        p_role text,
        p_login_email text,
        p_actor_user_id uuid
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare
        v_is_admin boolean:=false;
        v_manager public.staff_users%rowtype;
        v_requested_role text:=lower(trim(coalesce(p_role,'')));
        v_staff public.staff_users%rowtype;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
        if p_actor_user_id is null then raise exception 'Actor user is required'; end if;

        select exists(
          select 1 from public.partner_users pu
          where pu.user_id=p_actor_user_id
            and lower(coalesce(pu.role,''))='admin'
            and lower(coalesce(pu.status,''))='active'
            and pu.removed_at is null
        ) into v_is_admin;

        if not v_is_admin then
          select * into v_manager
          from public.staff_users su
          where su.user_id=p_actor_user_id
            and su.status='active'
            and su.role in ('manager','all_branch_manager')
          limit 1;
          if not found then raise exception 'Active Admin or Manager actor required'; end if;
        end if;

        if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then
          raise exception 'Valid Auth user is required';
        end if;
        if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
        if v_requested_role not in ('staff','manager') then raise exception 'Allowed roles: staff, manager'; end if;
        if not exists(select 1 from public.branches b where b.id=p_branch_id and b.status='active') then
          raise exception 'Active branch is required';
        end if;

        if not v_is_admin and v_manager.role='manager' then
          if v_requested_role<>'staff' then raise exception 'Branch Manager can only create Staff accounts'; end if;
          if v_manager.branch_id is null or p_branch_id is distinct from v_manager.branch_id then
            raise exception 'Branch Manager can only create Staff at assigned branch';
          end if;
        end if;

        insert into public.staff_users(user_id,branch_id,staff_name,role,status)
        values(p_new_user_id,p_branch_id,trim(p_staff_name),v_requested_role,'active')
        returning * into v_staff;

        insert into public.admin_audit_log(
          actor_user_id,action_type,entity_type,entity_id,after_data,metadata
        ) values (
          p_actor_user_id,'staff_account_created','staff_users',v_staff.id::text,
          jsonb_build_object('staff_name',v_staff.staff_name,'branch_id',v_staff.branch_id,'role',v_staff.role,'status',v_staff.status),
          jsonb_build_object('login_email',lower(trim(coalesce(p_login_email,''))),'secret_material_logged',false,'provisioning','hosted_adapter')
        );

        return jsonb_build_object('success',true,'staff',to_jsonb(v_staff));
      end;
      $fn$;
      revoke all on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) from public,anon,authenticated;
      grant execute on function public.admin_provision_staff(uuid,text,uuid,text,text,uuid) to service_role;
    $sql$;
  end if;
end
$migration$;
