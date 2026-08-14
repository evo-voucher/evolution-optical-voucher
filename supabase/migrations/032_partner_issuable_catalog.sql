-- Partner-safe issuable Voucher catalog v1
-- Purpose: let the Partner portal discover only Voucher Versions the current
-- authenticated Partner can actually issue, without direct reads of global
-- Voucher Engine tables.

create or replace function public.partner_issuable_voucher_catalog()
returns table(
  version_id uuid,
  template_id uuid,
  template_code text,
  template_name text,
  version_no integer,
  version_name text,
  voucher_label text,
  face_value numeric,
  discount_percent numeric,
  validity_mode text,
  valid_days integer,
  valid_months integer,
  valid_until date,
  usage_limit integer,
  transferable boolean,
  terms_text text,
  remaining_allocation bigint,
  remaining_supply bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner_id uuid;
  v_role text;
  v_staff_access_enabled boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select pu.partner_id,pu.role,p.staff_access_enabled
  into v_partner_id,v_role,v_staff_access_enabled
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and pu.status='active'
    and pu.removed_at is null
    and pu.role in ('partner_admin','partner_staff')
    and p.status='active'
  limit 1;

  if v_partner_id is null then
    raise exception 'Active Partner account not found';
  end if;

  if v_role='partner_staff' and not v_staff_access_enabled then
    raise exception 'Staff access is disabled by Partner Admin';
  end if;

  return query
  select
    vv.id,
    vt.id,
    vt.template_code,
    vt.template_name,
    vv.version_no,
    vv.version_name,
    case
      when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))||' '||vt.template_name
      when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'% '||vt.template_name
      else vt.template_name
    end as voucher_label,
    vv.face_value,
    vv.discount_percent,
    vv.validity_mode,
    vv.valid_days,
    vv.valid_months,
    vv.valid_until,
    vv.usage_limit,
    vv.transferable,
    vv.terms_text,
    greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0))::bigint as remaining_allocation,
    case
      when vv.supply_limit is null then null
      else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint
    end as remaining_supply
  from public.voucher_versions vv
  join public.voucher_templates vt
    on vt.id=vv.template_id
   and vt.status='active'
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
    select count(*)::bigint as issued_count
    from public.vouchers v
    where v.allocation_id=a.id
  ) ai on true
  left join lateral (
    select count(*)::bigint as issued_count
    from public.vouchers v
    where v.version_id=vv.id
  ) vi on true
  where vv.status='active'
    and (
      vv.validity_mode<>'fixed'
      or (
        (vv.valid_from is null or vv.valid_from<=v_today)
        and vv.valid_until is not null
        and vv.valid_until>=v_today
      )
    )
    and (a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0)>0
    and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
  order by vt.template_name,vv.version_no desc;
end;
$$;

revoke all on function public.partner_issuable_voucher_catalog() from public, anon;
grant execute on function public.partner_issuable_voucher_catalog() to authenticated;

comment on function public.partner_issuable_voucher_catalog() is
'Partner-only issuance catalog. Derives tenant from auth identity and returns only active, authorized, currently allocated Voucher Versions with remaining capacity.';
