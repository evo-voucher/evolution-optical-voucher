-- Converge Voucher and Redemption export RPCs with Production.
-- Production remains read-only reference.

CREATE OR REPLACE FUNCTION public.partner_export_vouchers(p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(voucher_code text, customer_name text, customer_phone text, customer_birthday date, customer_district text, voucher_type text, voucher_status text, expiry_date date, issued_at timestamp with time zone, issued_by_name text, usage_count integer, usage_limit integer, last_redeemed_at timestamp with time zone, last_branch_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb:=public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid:=(v_ctx->>'partner_id')::uuid;
begin
  return query
  select v.voucher_code,v.customer_name,v.customer_phone,pc.birth_date,pc.district,v.voucher_type,
    case when v.status='revoked' then 'revoked'
         when v.status='expired' or (v.status='active' and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired'
         when v.usage_count>=v.usage_limit then 'redeemed'
         else 'active' end::text,
    v.expiry_date,v.issued_at,v.issued_by_name,v.usage_count,v.usage_limit,lr.redeemed_at,lr.branch_name
  from public.vouchers v
  left join public.partner_customers pc on pc.id=v.customer_id and pc.partner_id=v.partner_id
  left join lateral (
    select r.redeemed_at,b.branch_name from public.redemptions r
    join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id and r.status='completed'
    order by r.redeemed_at desc limit 1
  ) lr on true
  where v.partner_id=v_partner_id
  order by v.issued_at desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_export_redemptions(p_branch_code text DEFAULT NULL::text)
 RETURNS TABLE(voucher_code text, customer_name text, voucher_type text, partner_name text, branch_name text, branch_code text, staff_name text, redeem_method text, redemption_status text, redeemed_at timestamp with time zone, notes text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_staff_portal_context();
  v_role text := v_ctx->>'role';
  v_home_branch_id uuid := nullif(v_ctx->>'branch_id','')::uuid;
  v_requested_branch_id uuid;
begin
  if nullif(trim(coalesce(p_branch_code,'')),'') is not null then
    select b.id into v_requested_branch_id
    from public.branches b
    where upper(b.branch_code)=upper(trim(p_branch_code)) and b.status='active'
    limit 1;
    if v_requested_branch_id is null then raise exception 'Active branch not found'; end if;
  end if;

  if v_role in ('staff','manager') then
    if v_home_branch_id is null then raise exception 'Staff account has no branch assignment'; end if;
    if v_requested_branch_id is not null and v_requested_branch_id<>v_home_branch_id then
      raise exception 'Branch export is outside your permitted scope';
    end if;
    v_requested_branch_id := v_home_branch_id;
  elsif v_role not in ('all_branch_manager','admin') then
    raise exception 'Staff export access denied';
  end if;

  return query
  select
    v.voucher_code,
    v.customer_name,
    v.voucher_type,
    p.partner_name,
    b.branch_name,
    b.branch_code,
    r.staff_name_snapshot,
    r.redeem_method,
    r.status,
    r.redeemed_at,
    r.notes
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  join public.partners p on p.id=r.partner_id
  join public.branches b on b.id=r.branch_id
  where v_requested_branch_id is null or r.branch_id=v_requested_branch_id
  order by r.redeemed_at desc;
end;
$function$
;
-- Align execute ACLs with Production.
revoke all on function public.partner_export_vouchers(uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_export_vouchers(uuid) to authenticated, service_role;

revoke all on function public.staff_export_redemptions(text) from public, anon, authenticated, service_role;
grant execute on function public.staff_export_redemptions(text) to authenticated, service_role;
