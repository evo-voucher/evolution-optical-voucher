-- Restore canonical Admin identity/provisioning after hosted compatibility.
-- Hosted production stores Admin in partner_users(role='admin'); canonical rebuilds
-- store Admin in admin_users. 047/049 intentionally adapt hosted production and
-- therefore override canonical behavior during a fresh rebuild.
--
-- Canonical marker rule: hosted production lacks vouchers.usage_limit and
-- vouchers.branch_scope_snapshotted, so this migration is a no-op there.

do $migration$
begin
  if exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) then
    execute $sql$
      create or replace function public.current_operational_realm()
      returns jsonb
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_partner public.partner_users%rowtype;
        v_staff public.staff_users%rowtype;
      begin
        if v_uid is null then
          return jsonb_build_object('authenticated',false,'realm',null);
        end if;

        if exists(
          select 1 from public.admin_users au
          where au.user_id=v_uid and au.status='active'
        ) then
          return jsonb_build_object('authenticated',true,'realm','admin','user_id',v_uid);
        end if;

        select * into v_partner
        from public.partner_users pu
        where pu.user_id=v_uid
          and pu.status='active'
          and pu.removed_at is null
        limit 1;
        if found then
          return jsonb_build_object(
            'authenticated',true,'realm','partner','user_id',v_uid,
            'partner_id',v_partner.partner_id,'role',v_partner.role
          );
        end if;

        select * into v_staff
        from public.staff_users su
        where su.user_id=v_uid and su.status='active'
        limit 1;
        if found then
          return jsonb_build_object(
            'authenticated',true,'realm','staff','user_id',v_uid,
            'branch_id',v_staff.branch_id,'role',v_staff.role
          );
        end if;

        return jsonb_build_object('authenticated',true,'realm',null,'user_id',v_uid);
      end;
      $fn$;

      revoke all on function public.current_operational_realm() from public,anon;
      grant execute on function public.current_operational_realm() to authenticated;

      create or replace function public.service_provision_partner(
        p_actor_user_id uuid,
        p_new_user_id uuid,
        p_partner_code text,
        p_partner_name text,
        p_contact_person text default null,
        p_contact_phone text default null,
        p_voucher_limit integer default 0,
        p_staff_limit integer default 0,
        p_login_email text default null
      )
      returns jsonb
      language sql
      security definer
      set search_path=public
      as $fn$
        select public.admin_provision_partner(
          p_partner_code,
          p_partner_name,
          p_contact_person,
          p_contact_phone,
          coalesce(p_voucher_limit,0),
          coalesce(p_staff_limit,0),
          p_new_user_id,
          p_login_email,
          p_actor_user_id
        );
      $fn$;

      revoke all on function public.service_provision_partner(uuid,uuid,text,text,text,text,integer,integer,text)
        from public,anon,authenticated;
      grant execute on function public.service_provision_partner(uuid,uuid,text,text,text,text,integer,integer,text)
        to service_role;
    $sql$;
  end if;
end
$migration$;
