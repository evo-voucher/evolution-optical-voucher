-- Restore canonical Partner Staff lifecycle semantics after hosted compatibility.
-- 051 intentionally supports the hosted legacy status vocabulary, including
-- status='inactive' for removed Partner Staff. Fresh canonical rebuilds instead
-- enforce partner_users.status in ('active','suspended','removed').
--
-- Canonical marker rule:
--   * canonical vouchers has usage_limit + branch_scope_snapshotted
--   * hosted legacy production does not
-- Therefore this migration is a no-op on hosted production and only restores
-- canonical lifecycle functions in fresh canonical environments.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.partner_update_staff_profile(
        p_staff_id uuid,
        p_action text,
        p_staff_name text,
        p_actor_user_id uuid
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path = public
      as $fn$
      declare
        v_actor public.partner_users%rowtype;
        v_partner public.partners%rowtype;
        v_target public.partner_users%rowtype;
        v_action text := lower(trim(coalesce(p_action,'')));
        v_now timestamptz := now();
        v_action_type text;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;

        select * into v_actor
        from public.partner_users pu
        where pu.user_id=p_actor_user_id
          and pu.role='partner_admin'
          and pu.status='active'
          and pu.removed_at is null
        limit 1;
        if not found then raise exception 'Active Partner Admin actor required'; end if;

        select * into v_partner from public.partners p
        where p.id=v_actor.partner_id and p.status='active';
        if not found then raise exception 'Active Partner required'; end if;

        select * into v_target
        from public.partner_users pu
        where pu.id=p_staff_id
          and pu.partner_id=v_partner.id
          and pu.role='partner_staff'
        for update;
        if not found then raise exception 'Partner Staff account not found'; end if;

        if v_action='rename' then
          if nullif(trim(coalesce(p_staff_name,'')),'') is null then raise exception 'Staff name is required'; end if;
          update public.partner_users
          set staff_name=trim(p_staff_name),updated_at=v_now
          where id=v_target.id returning * into v_target;
          v_action_type:='partner_staff_renamed';
        elsif v_action in ('suspend','activate') then
          if v_target.removed_at is not null or v_target.status='removed' then
            raise exception 'Removed Staff cannot be reactivated';
          end if;
          update public.partner_users
          set status=case when v_action='activate' then 'active' else 'suspended' end,
              updated_at=v_now
          where id=v_target.id returning * into v_target;
          v_action_type:='partner_staff_status_changed';
        elsif v_action='remove' then
          update public.partner_users
          set status='removed',removed_at=v_now,updated_at=v_now
          where id=v_target.id returning * into v_target;
          v_action_type:='partner_staff_removed';
        else
          raise exception 'Unsupported Partner Staff action';
        end if;

        insert into public.admin_audit_log(
          actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
        ) values (
          p_actor_user_id,coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),v_action_type,
          'partner_staff',v_target.id::text,v_partner.id,
          jsonb_build_object('staff_name',v_target.staff_name,'status',v_target.status,'removed_at',v_target.removed_at),
          jsonb_build_object('management','atomic_rpc','lifecycle','canonical')
        );

        return jsonb_build_object('success',true,'staff',to_jsonb(v_target));
      end;
      $fn$;

      create or replace function public.partner_record_staff_password_reset(
        p_staff_id uuid,
        p_actor_user_id uuid
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path = public
      as $fn$
      declare
        v_actor public.partner_users%rowtype;
        v_target public.partner_users%rowtype;
      begin
        if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;

        select * into v_actor from public.partner_users pu
        where pu.user_id=p_actor_user_id
          and pu.role='partner_admin'
          and pu.status='active'
          and pu.removed_at is null
        limit 1;
        if not found then raise exception 'Active Partner Admin actor required'; end if;

        select * into v_target from public.partner_users pu
        where pu.id=p_staff_id
          and pu.partner_id=v_actor.partner_id
          and pu.role='partner_staff'
          and pu.status<>'removed'
          and pu.removed_at is null;
        if not found then raise exception 'Active Partner Staff target required'; end if;

        insert into public.admin_audit_log(
          actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
        ) values (
          p_actor_user_id,coalesce(nullif(trim(v_actor.staff_name),''),'Partner Admin'),'partner_staff_password_reset',
          'partner_staff',v_target.id::text,v_actor.partner_id,
          jsonb_build_object('staff_name',v_target.staff_name,'login_email',v_target.login_email),
          jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true,'lifecycle','canonical')
        );

        return jsonb_build_object('success',true,'staff_id',v_target.id,'user_id',v_target.user_id,'staff_name',v_target.staff_name);
      end;
      $fn$;

      revoke all on function public.partner_update_staff_profile(uuid,text,text,uuid) from public,anon,authenticated;
      grant execute on function public.partner_update_staff_profile(uuid,text,text,uuid) to service_role;
      revoke all on function public.partner_record_staff_password_reset(uuid,uuid) from public,anon,authenticated;
      grant execute on function public.partner_record_staff_password_reset(uuid,uuid) to service_role;
    $sql$;
  end if;
end
$migration$;
