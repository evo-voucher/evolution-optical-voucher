-- Read-only customer reporting dates for PDF/Excel reporting.
-- Date Received = earliest voucher issued_at for the customer.
-- Redeemed      = latest completed/success redemption redeemed_at for any voucher owned by the customer.

create or replace function public.admin_customer_reporting_dates(p_partner_id uuid default null)
returns table(
  customer_id uuid,
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
    pc.id as customer_id,
    min(v.issued_at) filter (where v.issued_at is not null) as date_received_at,
    max(r.redeemed_at) filter (
      where lower(coalesce(r.status,'')) in ('success','completed')
        and r.redeemed_at is not null
    ) as redeemed_at
  from public.partner_customers pc
  left join public.vouchers v on v.customer_id = pc.id
  left join public.redemptions r on r.voucher_id = v.id
  where p_partner_id is null or pc.partner_id = p_partner_id
  group by pc.id;
end;
$function$;

revoke all on function public.admin_customer_reporting_dates(uuid) from public, anon;
grant execute on function public.admin_customer_reporting_dates(uuid) to authenticated;
