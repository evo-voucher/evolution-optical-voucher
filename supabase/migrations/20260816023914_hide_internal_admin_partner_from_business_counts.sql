-- Hide internal ADMIN identity anchor from business-facing Partner counts/directory.
-- Production-applied: 2026-08-16

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date; v_result jsonb;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  select jsonb_build_object(
    'partners_total',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))<>'archived'),
    'partners_active',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))='active'),
    'vouchers_total',(select count(*) from public.vouchers),
    'vouchers_active',(select count(*) from public.vouchers v where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today),
    'vouchers_redeemed',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired'))),
    'vouchers_expired',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today)),
    'vouchers_revoked',(select count(*) from public.vouchers v where lower(coalesce(v.status,''))='revoked'),
    'redemptions_completed',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed')),
    'redemptions_reversed',(select count(*) from public.redemptions r where lower(coalesce(r.status,''))='reversed'),
    'redemptions_today',(select count(*) from public.redemptions r where lower(coalesce(r.status,'')) in ('success','completed') and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today)
  ) into v_result;
  return v_result;
end;$function$;

create or replace function public.admin_partner_directory()
returns table(partner_id uuid, partner_code text, partner_name text, partner_status text, voucher_limit integer, vouchers_issued bigint, staff_limit integer, partner_staff_count bigint, staff_access_enabled boolean)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query select p.id,p.partner_code,p.partner_name,p.status,p.voucher_limit,
    (select count(*) from public.vouchers v where v.partner_id=p.id),p.staff_limit,
    (select count(*) from public.partner_users pu where pu.partner_id=p.id and lower(coalesce(pu.role,''))='partner_staff' and pu.removed_at is null and lower(coalesce(pu.status,''))<>'removed'),
    p.staff_access_enabled
  from public.partners p
  where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))<>'archived'
  order by p.partner_name,p.partner_code;
end;$function$;
