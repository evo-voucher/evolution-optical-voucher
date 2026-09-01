-- Converge Admin Voucher Version and Allocation catalog RPCs with Production.
-- Production remains read-only reference.

CREATE OR REPLACE FUNCTION public.admin_active_voucher_allocations()
 RETURNS TABLE(allocation_id uuid, partner_id uuid, partner_code text, partner_name text, version_id uuid, version_name text, quantity_allocated integer, issued_count bigint, remaining_unissued bigint, validity_anchor text, validity_value integer, validity_unit text, valid_until timestamp with time zone, all_branches boolean, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    a.id,
    p.id,
    p.partner_code,
    p.partner_name,
    vv.id,
    vv.version_name,
    a.quantity_allocated,
    coalesce(vx.issued_count,0)::bigint,
    greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(vx.issued_count,0))::bigint,
    a.validity_anchor,
    a.validity_value,
    a.validity_unit,
    a.valid_until,
    a.all_branches,
    a.created_at
  from public.partner_voucher_allocations a
  join public.partners p on p.id=a.partner_id
  join public.voucher_versions vv on vv.id=a.version_id
  left join lateral (
    select count(*)::bigint as issued_count
    from public.vouchers v
    where v.allocation_id=a.id
  ) vx on true
  where public.is_voucher_admin()
    and a.status='active'
    and p.status='active'
    and vv.status='active'
    and greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(vx.issued_count,0))>0
  order by a.created_at asc;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_active_voucher_versions()
 RETURNS TABLE(version_id uuid, template_id uuid, template_code text, template_name text, version_no integer, version_name text, voucher_label text, validity_mode text, valid_days integer, valid_months integer, valid_until date, supply_limit integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query
  select vv.id,vt.id,vt.template_code,vt.template_name,vv.version_no,vv.version_name,
    vt.template_code as voucher_label,
    vv.validity_mode,vv.valid_days,vv.valid_months,vv.valid_until,vv.supply_limit
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id
  where vv.status='active' and vt.status='active'
  order by lower(vt.template_code), vv.version_no desc;
end;
$function$
;
-- Align execute ACLs with Production.
revoke all on function public.admin_active_voucher_versions() from public, anon, authenticated, service_role;
grant execute on function public.admin_active_voucher_versions() to authenticated, service_role;

revoke all on function public.admin_active_voucher_allocations() from public, anon, authenticated, service_role;
grant execute on function public.admin_active_voucher_allocations() to authenticated;
