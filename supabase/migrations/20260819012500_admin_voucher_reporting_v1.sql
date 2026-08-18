-- Admin voucher reporting v1.
-- Read-only reporting expansion: system issued total, per-Partner lifecycle counts,
-- and voucher-type breakdown. No voucher issuance/redemption mutation logic changes.

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  select jsonb_build_object(
    'partners_total',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))<>'archived'),
    'partners_active',(select count(*) from public.partners p where upper(coalesce(p.partner_code,''))<>'ADMIN' and lower(coalesce(p.status,''))='active'),
    'vouchers_total',(select count(*) from public.vouchers),
    'vouchers_issued',(select count(*) from public.vouchers v where v.issued_at is not null),
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
$function$;

create or replace function public.admin_partner_reporting_summary()
returns table(
  partner_id uuid,
  vouchers_issued bigint,
  vouchers_active bigint,
  vouchers_redeemed bigint,
  vouchers_expired bigint,
  vouchers_revoked bigint
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  return query
  select
    p.id,
    count(v.id) filter (where v.issued_at is not null)::bigint,
    count(v.id) filter (where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today)::bigint,
    count(v.id) filter (where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))::bigint,
    count(v.id) filter (where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))::bigint,
    count(v.id) filter (where lower(coalesce(v.status,''))='revoked')::bigint
  from public.partners p
  left join public.vouchers v on v.partner_id=p.id
  where upper(coalesce(p.partner_code,''))<>'ADMIN'
    and lower(coalesce(p.status,''))<>'archived'
  group by p.id
  order by p.id;
end;
$function$;

create or replace function public.admin_voucher_type_summary(p_partner_id uuid default null)
returns table(
  partner_id uuid,
  partner_name text,
  voucher_type text,
  vouchers_total bigint,
  vouchers_issued bigint,
  vouchers_active bigint,
  vouchers_redeemed bigint,
  vouchers_expired bigint,
  vouchers_revoked bigint
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;

  return query
  select
    v.partner_id,
    p.partner_name,
    coalesce(nullif(trim(v.voucher_type),''),'Unspecified') as voucher_type,
    count(*)::bigint,
    count(*) filter (where v.issued_at is not null)::bigint,
    count(*) filter (where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today)::bigint,
    count(*) filter (where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))::bigint,
    count(*) filter (where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))::bigint,
    count(*) filter (where lower(coalesce(v.status,''))='revoked')::bigint
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  where (p_partner_id is null or v.partner_id=p_partner_id)
    and upper(coalesce(p.partner_code,''))<>'ADMIN'
  group by v.partner_id,p.partner_name,coalesce(nullif(trim(v.voucher_type),''),'Unspecified')
  order by p.partner_name,coalesce(nullif(trim(v.voucher_type),''),'Unspecified');
end;
$function$;

revoke all on function public.admin_partner_reporting_summary() from public;
revoke all on function public.admin_voucher_type_summary(uuid) from public;
grant execute on function public.admin_partner_reporting_summary() to authenticated;
grant execute on function public.admin_voucher_type_summary(uuid) to authenticated;
