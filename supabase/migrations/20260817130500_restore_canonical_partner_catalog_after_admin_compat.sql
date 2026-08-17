-- Restore the canonical Partner voucher catalog after the hosted/admin compatibility
-- migrations that are intentionally retained for the legacy hosted lineage.
--
-- On a fresh canonical rebuild, 20260816023543 runs after migration 059 and can
-- replace partner_issuable_voucher_catalog() with a legacy implementation that
-- references voucher_versions.validity_type. Canonical voucher_versions uses
-- validity_mode instead. Keep Admin superuser compatibility, but restore the
-- canonical column contract whenever canonical markers are present.

do $migration$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='usage_limit'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='vouchers' and column_name='branch_scope_snapshotted'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='voucher_versions' and column_name='validity_mode'
  ) then
    execute $sql$
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

        select pu.partner_id,lower(coalesce(pu.role,'')),coalesce(p.staff_access_enabled,false)
        into v_partner_id,v_role,v_staff_access_enabled
        from public.partner_users pu
        join public.partners p on p.id=pu.partner_id
        where pu.user_id=v_uid
          and lower(coalesce(pu.status,''))='active'
          and pu.removed_at is null
          and lower(coalesce(pu.role,'')) in ('admin','partner_admin','partner_staff')
          and lower(coalesce(p.status,''))='active'
        order by case when lower(coalesce(pu.role,''))='admin' then 0 else 1 end
        limit 1;

        if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
        if v_role='partner_staff' and not v_staff_access_enabled then
          raise exception 'Staff access is disabled by Partner Admin';
        end if;

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
        join public.partner_voucher_access pva
          on pva.partner_id=v_partner_id
         and pva.template_id=vv.template_id
         and pva.status='active'
         and (pva.valid_from is null or pva.valid_from<=now())
         and (pva.valid_until is null or pva.valid_until>=now())
        join lateral (
          select pa.id,pa.quantity_allocated,pa.quantity_revoked
          from public.partner_voucher_allocations pa
          where pa.partner_id=v_partner_id
            and pa.version_id=vv.id
            and pa.status='active'
            and (pa.valid_from is null or pa.valid_from<=now())
            and (pa.valid_until is null or pa.valid_until>=now())
          order by pa.created_at desc
          limit 1
        ) a on true
        left join lateral (
          select count(*)::bigint issued_count
          from public.vouchers v
          where v.allocation_id=a.id
        ) ai on true
        left join lateral (
          select count(*)::bigint issued_count
          from public.vouchers v
          where v.version_id=vv.id
        ) vi on true
        where vv.status='active'
          and (
            vv.validity_mode<>'fixed'
            or ((vv.valid_from is null or vv.valid_from<=v_today)
                and vv.valid_until is not null
                and vv.valid_until>=v_today)
          )
          and (a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0)>0
          and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
        order by vt.template_name,vv.version_no desc;
      end;
      $fn$;

      revoke all on function public.partner_issuable_voucher_catalog() from public,anon;
      grant execute on function public.partner_issuable_voucher_catalog() to authenticated;
    $sql$;
  end if;
end;
$migration$;
