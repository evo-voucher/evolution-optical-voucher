-- Canonical Portal read-model consolidation.
--
-- Hosted compatibility migrations 047/050 intentionally adapt the existing
-- production lineage. On a fresh canonical rebuild, 050 must not remain the
-- owner of Portal read semantics because canonical differs in important ways:
--   * vouchers are multi-use (usage_limit / usage_count are authoritative)
--   * redemptions.staff_user_id stores the Auth user id
--   * canonical voucher status is active/redeemed/expired/revoked
--
-- This migration restores the canonical Admin/Partner/Staff read boundary in
-- one place instead of adding one-off restore migrations per browser failure.
-- Existing hosted production has no canonical markers below, so this is a no-op
-- there.

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
      create or replace function public.partner_voucher_summary()
      returns jsonb
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_partner_id uuid:=public.current_partner_id();
        v_today date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
      begin
        if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
        return jsonb_build_object(
          'partner_id',v_partner_id,
          'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
          'active_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='active' and v.expiry_date>=v_today and v.usage_count<v.usage_limit),
          'redeemed_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and not (v.status='expired' or (v.status='active' and v.expiry_date<v_today)) and v.usage_count>=v.usage_limit),
          'expired_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))),
          'revoked_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='revoked'),
          'completed_redemptions',(select count(*) from public.redemptions r where r.partner_id=v_partner_id and r.status='completed')
        );
      end;
      $fn$;

      create or replace function public.partner_recent_vouchers(p_limit integer default 50)
      returns table(
        voucher_id uuid,voucher_code text,customer_name text,customer_phone text,
        voucher_type text,voucher_status text,expiry_date date,issued_at timestamptz,
        issued_by_name text,usage_count integer,usage_limit integer,
        last_redeemed_at timestamptz,last_branch_name text
      )
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare v_partner_id uuid:=public.current_partner_id();
      begin
        if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
        if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500'; end if;
        return query
        select v.id,v.voucher_code,v.customer_name,v.customer_phone,v.voucher_type,
          case when v.status='revoked' then 'revoked'
               when v.status='expired' or (v.status='active' and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired'
               when v.usage_count>=v.usage_limit then 'redeemed' else 'active' end,
          v.expiry_date,v.issued_at,v.issued_by_name,v.usage_count,v.usage_limit,
          lr.redeemed_at,lr.branch_name
        from public.vouchers v
        left join lateral (
          select r.redeemed_at,b.branch_name
          from public.redemptions r
          join public.branches b on b.id=r.branch_id
          where r.voucher_id=v.id and r.status='completed'
          order by r.redeemed_at desc limit 1
        ) lr on true
        where v.partner_id=v_partner_id
        order by v.issued_at desc
        limit p_limit;
      end;
      $fn$;

      create or replace function public.partner_issuable_voucher_catalog()
      returns table(
        version_id uuid,template_id uuid,template_code text,template_name text,
        version_no integer,version_name text,voucher_label text,face_value numeric,
        discount_percent numeric,validity_mode text,valid_days integer,valid_months integer,
        valid_until date,usage_limit integer,transferable boolean,terms_text text,
        remaining_allocation bigint,remaining_supply bigint
      )
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_partner_id uuid;
        v_role text;
        v_staff_access_enabled boolean;
        v_today date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
      begin
        if v_uid is null then raise exception 'Authentication required'; end if;
        select pu.partner_id,pu.role,p.staff_access_enabled
        into v_partner_id,v_role,v_staff_access_enabled
        from public.partner_users pu join public.partners p on p.id=pu.partner_id
        where pu.user_id=v_uid and pu.status='active' and pu.removed_at is null
          and pu.role in ('partner_admin','partner_staff') and p.status='active'
        limit 1;
        if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
        if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;
        return query
        select vv.id,vt.id,vt.template_code,vt.template_name,vv.version_no,vv.version_name,
          case when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))||' '||vt.template_name
               when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'% '||vt.template_name
               else vt.template_name end,
          vv.face_value,vv.discount_percent,vv.validity_mode,vv.valid_days,vv.valid_months,
          vv.valid_until,vv.usage_limit,vv.transferable,vv.terms_text,
          greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0))::bigint,
          case when vv.supply_limit is null then null else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint end
        from public.voucher_versions vv
        join public.voucher_templates vt on vt.id=vv.template_id and vt.status='active'
        join public.partner_voucher_access pva on pva.partner_id=v_partner_id and pva.template_id=vv.template_id
          and pva.status='active' and (pva.valid_from is null or pva.valid_from<=now()) and (pva.valid_until is null or pva.valid_until>=now())
        join lateral (
          select pa.id,pa.quantity_allocated,pa.quantity_revoked
          from public.partner_voucher_allocations pa
          where pa.partner_id=v_partner_id and pa.version_id=vv.id and pa.status='active'
            and (pa.valid_from is null or pa.valid_from<=now()) and (pa.valid_until is null or pa.valid_until>=now())
          order by pa.created_at desc limit 1
        ) a on true
        left join lateral (select count(*)::bigint issued_count from public.vouchers v where v.allocation_id=a.id) ai on true
        left join lateral (select count(*)::bigint issued_count from public.vouchers v where v.version_id=vv.id) vi on true
        where vv.status='active'
          and (vv.validity_mode<>'fixed' or ((vv.valid_from is null or vv.valid_from<=v_today) and vv.valid_until is not null and vv.valid_until>=v_today))
          and (a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0)>0
          and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
        order by vt.template_name,vv.version_no desc;
      end;
      $fn$;

      create or replace function public.partner_staff_directory()
      returns table(
        staff_id uuid,user_id uuid,staff_name text,login_email text,staff_status text,
        created_at timestamptz,updated_at timestamptz,removed_at timestamptz
      )
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare v_partner_id uuid;
      begin
        select pu.partner_id into v_partner_id
        from public.partner_users pu join public.partners p on p.id=pu.partner_id
        where pu.user_id=(select auth.uid()) and pu.role='partner_admin' and pu.status='active'
          and pu.removed_at is null and p.status='active' limit 1;
        if v_partner_id is null then raise exception 'Active Partner Admin access required'; end if;
        return query
        select pu.id,pu.user_id,pu.staff_name,pu.login_email,pu.status,pu.created_at,pu.updated_at,pu.removed_at
        from public.partner_users pu
        where pu.partner_id=v_partner_id and pu.role='partner_staff'
        order by (pu.removed_at is not null),lower(coalesce(pu.staff_name,'')),pu.created_at;
      end;
      $fn$;

      create or replace function public.staff_operational_context()
      returns jsonb
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_staff public.staff_users%rowtype;
        v_branch public.branches%rowtype;
        v_branches jsonb:='[]'::jsonb;
      begin
        if v_uid is null then raise exception 'Authentication required'; end if;
        select * into v_staff from public.staff_users su where su.user_id=v_uid and su.status='active' limit 1;
        if not found then raise exception 'Active Staff account not found'; end if;
        if v_staff.role='all_branch_manager' then
          select coalesce(jsonb_agg(jsonb_build_object('branch_id',b.id,'branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb)
          into v_branches from public.branches b where b.status='active';
        else
          if v_staff.branch_id is null then raise exception 'Staff account has no branch assigned'; end if;
          select * into v_branch from public.branches b where b.id=v_staff.branch_id and b.status='active';
          if not found then raise exception 'Assigned branch is not active'; end if;
          v_branches:=jsonb_build_array(jsonb_build_object('branch_id',v_branch.id,'branch_code',v_branch.branch_code,'branch_name',v_branch.branch_name,'address',v_branch.address,'phone',v_branch.phone));
        end if;
        return jsonb_build_object('success',true,'staff_user_id',v_uid,'staff_name',v_staff.staff_name,'role',v_staff.role,'branch_id',v_staff.branch_id,'branch_selection_required',v_staff.role='all_branch_manager','branches',v_branches);
      end;
      $fn$;

      create or replace function public.staff_today_summary()
      returns jsonb
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_staff public.staff_users%rowtype;
        v_today date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;
        v_count bigint;
      begin
        if v_uid is null then raise exception 'Authentication required'; end if;
        select * into v_staff from public.staff_users su where su.user_id=v_uid and su.status='active' limit 1;
        if not found then raise exception 'Active Staff account not found'; end if;
        select count(*) into v_count from public.redemptions r
        where r.status='completed' and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
          and (v_staff.role='all_branch_manager' or (v_staff.role='manager' and r.branch_id=v_staff.branch_id) or (v_staff.role='staff' and r.staff_user_id=v_uid));
        return jsonb_build_object('success',true,'staff_user_id',v_uid,'staff_name',v_staff.staff_name,'role',v_staff.role,'branch_id',v_staff.branch_id,'today_redeemed',v_count);
      end;
      $fn$;

      create or replace function public.staff_recent_redemptions(p_limit integer default 20)
      returns table(
        redemption_id uuid,voucher_id uuid,voucher_code text,customer_name text,voucher_type text,
        partner_name text,branch_id uuid,branch_name text,staff_name text,redeem_method text,
        redemption_status text,redeemed_at timestamptz,notes text
      )
      language plpgsql
      stable
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_staff public.staff_users%rowtype;
      begin
        if v_uid is null then raise exception 'Authentication required'; end if;
        if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Limit must be between 1 and 100'; end if;
        select * into v_staff from public.staff_users su where su.user_id=v_uid and su.status='active' limit 1;
        if not found then raise exception 'Active Staff account not found'; end if;
        return query
        select r.id,r.voucher_id,v.voucher_code,v.customer_name,v.voucher_type,p.partner_name,
          r.branch_id,b.branch_name,r.staff_name_snapshot,r.redeem_method,r.status,r.redeemed_at,r.notes
        from public.redemptions r
        join public.vouchers v on v.id=r.voucher_id
        join public.partners p on p.id=r.partner_id
        join public.branches b on b.id=r.branch_id
        where v_staff.role='all_branch_manager'
           or (v_staff.role='manager' and r.branch_id=v_staff.branch_id)
           or (v_staff.role='staff' and r.staff_user_id=v_uid)
        order by r.redeemed_at desc limit p_limit;
      end;
      $fn$;

      create or replace function public.verify_voucher(p_voucher_code text,p_branch_code text default null)
      returns jsonb
      language plpgsql
      security definer
      set search_path=public
      as $fn$
      declare
        v_uid uuid:=(select auth.uid());
        v_staff public.staff_users%rowtype;
        v_voucher public.vouchers%rowtype;
        v_branch_id uuid;
        v_branch_name text;
        v_allowed boolean:=false;
        v_expired boolean:=false;
        v_display_status text;
      begin
        if v_uid is null then return jsonb_build_object('success',false,'error','Authentication required'); end if;
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
        select * into v_voucher from public.vouchers v where upper(v.voucher_code)=upper(trim(p_voucher_code)) limit 1;
        if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
        v_expired:=v_voucher.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date;
        if v_voucher.all_branches then v_allowed:=true;
        else select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
        end if;
        v_display_status:=case when v_voucher.status='active' and v_expired then 'expired' when v_voucher.status='active' then 'valid' else v_voucher.status end;
        return jsonb_build_object(
          'success',true,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'customer_name',v_voucher.customer_name,
          'customer_phone',v_voucher.customer_phone,'voucher_type',v_voucher.voucher_type,'expiry_date',v_voucher.expiry_date,
          'status',v_display_status,'canonical_status',v_voucher.status,'usage_limit',v_voucher.usage_limit,'usage_count',v_voucher.usage_count,
          'remaining_uses',greatest(0,v_voucher.usage_limit-v_voucher.usage_count),'branch_id',v_branch_id,'branch_name',v_branch_name,
          'branch_allowed',v_allowed,'expired',v_expired,
          'can_redeem',v_voucher.status='active' and not v_expired and v_allowed and v_voucher.usage_count<v_voucher.usage_limit
        );
      end;
      $fn$;

      revoke all on function public.partner_voucher_summary() from public,anon;
      grant execute on function public.partner_voucher_summary() to authenticated;
      revoke all on function public.partner_recent_vouchers(integer) from public,anon;
      grant execute on function public.partner_recent_vouchers(integer) to authenticated;
      revoke all on function public.partner_issuable_voucher_catalog() from public,anon;
      grant execute on function public.partner_issuable_voucher_catalog() to authenticated;
      revoke all on function public.partner_staff_directory() from public,anon;
      grant execute on function public.partner_staff_directory() to authenticated;
      revoke all on function public.staff_operational_context() from public,anon;
      grant execute on function public.staff_operational_context() to authenticated;
      revoke all on function public.staff_today_summary() from public,anon;
      grant execute on function public.staff_today_summary() to authenticated;
      revoke all on function public.staff_recent_redemptions(integer) from public,anon;
      grant execute on function public.staff_recent_redemptions(integer) to authenticated;
      revoke all on function public.verify_voucher(text,text) from public,anon;
      grant execute on function public.verify_voucher(text,text) to authenticated;
    $sql$;
  end if;
end
$migration$;
