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

create or replace function public.admin_partner_directory()
returns table(
  partner_id uuid,
  partner_code text,
  partner_name text,
  partner_status text,
  voucher_limit integer,
  vouchers_issued bigint,
  vouchers_active bigint,
  vouchers_redeemed bigint,
  vouchers_expired bigint,
  vouchers_revoked bigint,
  staff_limit integer,
  partner_staff_count bigint,
  staff_access_enabled boolean
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
    p.partner_code,
    p.partner_name,
    p.status,
    p.voucher_limit,
    (select count(*) from public.vouchers v where v.partner_id=p.id and v.issued_at is not null),
    (select count(*) from public.vouchers v where v.partner_id=p.id and lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today),
    (select count(*) from public.vouchers v where v.partner_id=p.id and (lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))),
    (select count(*) from public.vouchers v where v.partner_id=p.id and (lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))),
    (select count(*) from public.vouchers v where v.partner_id=p.id and lower(coalesce(v.status,''))='revoked'),
    p.staff_limit,
    (select count(*) from public.partner_users pu where pu.partner_id=p.id and lower(coalesce(pu.role,''))='partner_staff' and pu.removed_at is null and lower(coalesce(pu.status,''))<>'removed'),
    p.staff_access_enabled
  from public.partners p
  where upper(coalesce(p.partner_code,''))<>'ADMIN'
    and lower(coalesce(p.status,''))<>'archived'
  order by p.partner_name,p.partner_code;
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
    count(*)::bigint as vouchers_total,
    count(*) filter (where v.issued_at is not null)::bigint as vouchers_issued,
    count(*) filter (where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today)::bigint as vouchers_active,
    count(*) filter (where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))::bigint as vouchers_redeemed,
    count(*) filter (where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))::bigint as vouchers_expired,
    count(*) filter (where lower(coalesce(v.status,''))='revoked')::bigint as vouchers_revoked
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  where (p_partner_id is null or v.partner_id=p_partner_id)
    and upper(coalesce(p.partner_code,''))<>'ADMIN'
  group by v.partner_id,p.partner_name,coalesce(nullif(trim(v.voucher_type),''),'Unspecified')
  order by p.partner_name,coalesce(nullif(trim(v.voucher_type),''),'Unspecified');
end;
$function$;

revoke all on function public.admin_voucher_type_summary(uuid) from public;
grant execute on function public.admin_voucher_type_summary(uuid) to authenticated;
