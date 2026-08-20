begin;

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select jsonb_build_object(
    'partners_total',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))<>'archived'),
    'partners_active',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))='active'),
    'vouchers_allocated',(select coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0) from public.partner_voucher_allocations a join public.partners p on p.id=a.partner_id where upper(coalesce(p.partner_code,''))<>'ADMIN'),
    'vouchers_issued',(select count(*) from public.vouchers v where v.issued_at is not null),
    'vouchers_total',(select count(*) from public.vouchers),
    'allocation_remaining',greatest(0,
      (select coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0) from public.partner_voucher_allocations a join public.partners p on p.id=a.partner_id where upper(coalesce(p.partner_code,''))<>'ADMIN')
      -(select count(*) from public.vouchers v where v.issued_at is not null)
    ),
    'vouchers_active',(select count(*) from public.vouchers v where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today),
    'vouchers_redeemed',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired'))),
    'vouchers_expired',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today)),
    'vouchers_revoked',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='revoked'),
    'redemptions_completed',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed')),
    'redemptions_reversed',(select count(*) from public.redemptions r where lower(coalesce(r.status,''))='reversed'),
    'redemptions_today',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed') and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today)
  ) into v_result;

  return v_result;
end;
$$;

commit;
