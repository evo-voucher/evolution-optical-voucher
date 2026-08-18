-- Admin voucher reporting v1.
-- Read-only reporting expansion.
-- Important business distinction:
--   allocation = stock Admin gives to a Partner
--   issuance   = an actual customer Voucher materialised from that stock
-- No issuance/redemption mutation logic or table structure is changed here.

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
    'vouchers_allocated',(select coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0) from public.partner_voucher_allocations a join public.partners p on p.id=a.partner_id where upper(coalesce(p.partner_code,''))<>'ADMIN'),
    'vouchers_issued',(select count(*) from public.vouchers v where v.issued_at is not null),
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
$function$;

create or replace function public.admin_partner_reporting_summary()
returns table(
  partner_id uuid,
  vouchers_allocated bigint,
  vouchers_issued bigint,
  allocation_remaining bigint,
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
  with alloc as (
    select a.partner_id,
      coalesce(sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0))),0)::bigint as allocated
    from public.partner_voucher_allocations a
    group by a.partner_id
  ), issued as (
    select v.partner_id,
      count(*) filter (where v.issued_at is not null)::bigint as issued,
      count(*) filter (where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today)::bigint as active,
      count(*) filter (where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))::bigint as redeemed,
      count(*) filter (where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))::bigint as expired,
      count(*) filter (where lower(coalesce(v.status,''))='revoked')::bigint as revoked
    from public.vouchers v
    group by v.partner_id
  )
  select p.id,
    coalesce(a.allocated,0)::bigint,
    coalesce(i.issued,0)::bigint,
    greatest(0,coalesce(a.allocated,0)-coalesce(i.issued,0))::bigint,
    coalesce(i.active,0)::bigint,
    coalesce(i.redeemed,0)::bigint,
    coalesce(i.expired,0)::bigint,
    coalesce(i.revoked,0)::bigint
  from public.partners p
  left join alloc a on a.partner_id=p.id
  left join issued i on i.partner_id=p.id
  where upper(coalesce(p.partner_code,''))<>'ADMIN'
    and lower(coalesce(p.status,''))<>'archived'
  order by p.id;
end;
$function$;

create or replace function public.admin_voucher_type_summary(p_partner_id uuid default null)
returns table(
  partner_id uuid,
  partner_name text,
  voucher_type text,
  vouchers_allocated bigint,
  vouchers_issued bigint,
  allocation_remaining bigint,
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
  with alloc as (
    select a.partner_id,vv.id as version_id,
      coalesce(nullif(trim(vt.template_name),''),'Unspecified') as voucher_type,
      sum(greatest(0,coalesce(a.quantity_allocated,0)-coalesce(a.quantity_revoked,0)))::bigint as allocated
    from public.partner_voucher_allocations a
    join public.voucher_versions vv on vv.id=a.version_id
    join public.voucher_templates vt on vt.id=vv.template_id
    where p_partner_id is null or a.partner_id=p_partner_id
    group by a.partner_id,vv.id,coalesce(nullif(trim(vt.template_name),''),'Unspecified')
  ), issued as (
    select v.partner_id,v.version_id,
      count(*) filter (where v.issued_at is not null)::bigint as issued,
      count(*) filter (where lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date>=v_today)::bigint as active,
      count(*) filter (where lower(coalesce(v.status,''))='redeemed' or (coalesce(v.usage_count,0)>0 and lower(coalesce(v.status,'')) not in ('revoked','expired')))::bigint as redeemed,
      count(*) filter (where lower(coalesce(v.status,''))='expired' or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today))::bigint as expired,
      count(*) filter (where lower(coalesce(v.status,''))='revoked')::bigint as revoked
    from public.vouchers v
    where p_partner_id is null or v.partner_id=p_partner_id
    group by v.partner_id,v.version_id
  ), combined as (
    select coalesce(a.partner_id,i.partner_id) as partner_id,
      coalesce(a.version_id,i.version_id) as version_id,
      coalesce(a.voucher_type,
        (select coalesce(nullif(trim(vt.template_name),''),'Unspecified') from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id where vv.id=i.version_id),
        'Unspecified') as voucher_type,
      coalesce(a.allocated,0)::bigint as allocated,
      coalesce(i.issued,0)::bigint as issued,
      coalesce(i.active,0)::bigint as active,
      coalesce(i.redeemed,0)::bigint as redeemed,
      coalesce(i.expired,0)::bigint as expired,
      coalesce(i.revoked,0)::bigint as revoked
    from alloc a
    full join issued i on i.partner_id=a.partner_id and i.version_id=a.version_id
  )
  select c.partner_id,p.partner_name,c.voucher_type,
    sum(c.allocated)::bigint,
    sum(c.issued)::bigint,
    greatest(0,sum(c.allocated)-sum(c.issued))::bigint,
    sum(c.active)::bigint,
    sum(c.redeemed)::bigint,
    sum(c.expired)::bigint,
    sum(c.revoked)::bigint
  from combined c
  join public.partners p on p.id=c.partner_id
  where upper(coalesce(p.partner_code,''))<>'ADMIN'
  group by c.partner_id,p.partner_name,c.voucher_type
  order by p.partner_name,c.voucher_type;
end;
$function$;

revoke all on function public.admin_partner_reporting_summary() from public;
revoke all on function public.admin_voucher_type_summary(uuid) from public;
grant execute on function public.admin_partner_reporting_summary() to authenticated;
grant execute on function public.admin_voucher_type_summary(uuid) to authenticated;
