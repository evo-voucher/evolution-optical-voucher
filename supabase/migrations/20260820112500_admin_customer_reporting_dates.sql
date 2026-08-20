-- Read-only voucher-level customer report for PDF/Excel reporting.
-- One voucher = one row.
-- Date Received = voucher issued_at.
-- Redeemed      = latest completed/success redemption redeemed_at for that voucher.

create or replace function public.admin_customer_voucher_report(p_partner_id uuid default null)
returns table(
  voucher_id uuid,
  customer_id uuid,
  partner_id uuid,
  partner_code text,
  partner_name text,
  customer_name text,
  customer_phone text,
  customer_birthday date,
  customer_district text,
  voucher_code text,
  voucher_type text,
  date_received_at timestamptz,
  redeemed_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    v.id as voucher_id,
    pc.id as customer_id,
    pc.partner_id,
    p.partner_code,
    p.partner_name,
    pc.customer_name,
    pc.customer_phone,
    pc.birth_date as customer_birthday,
    pc.district as customer_district,
    v.voucher_code,
    coalesce(nullif(trim(vt.template_name),''),'Unspecified') as voucher_type,
    v.issued_at as date_received_at,
    rr.redeemed_at
  from public.vouchers v
  join public.partner_customers pc on pc.id = v.customer_id
  join public.partners p on p.id = pc.partner_id
  left join public.voucher_versions vv on vv.id = v.version_id
  left join public.voucher_templates vt on vt.id = vv.template_id
  left join lateral (
    select max(r.redeemed_at) as redeemed_at
    from public.redemptions r
    where r.voucher_id = v.id
      and lower(coalesce(r.status,'')) in ('success','completed')
      and r.redeemed_at is not null
  ) rr on true
  where (p_partner_id is null or pc.partner_id = p_partner_id)
    and v.issued_at is not null
  order by
    coalesce(pc.district,''),
    upper(coalesce(p.partner_code,'')),
    upper(coalesce(pc.customer_name,'')),
    v.issued_at,
    v.voucher_code;
end;
$function$;

revoke all on function public.admin_customer_voucher_report(uuid) from public, anon;
grant execute on function public.admin_customer_voucher_report(uuid) to authenticated;
