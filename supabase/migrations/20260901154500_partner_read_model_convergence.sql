-- Converge Partner dashboard and read-model RPCs with Production.
-- Production remains read-only reference.
-- Retire legacy overloads first to prevent PostgREST ambiguity.

drop function if exists public.partner_voucher_summary();
drop function if exists public.get_my_partner_dashboard();
drop function if exists public.get_my_partner_claim_access();
drop function if exists public.partner_recent_vouchers(integer);
drop function if exists public.partner_issuable_voucher_catalog();

CREATE OR REPLACE FUNCTION public.get_my_partner_claim_access(p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner uuid := (v_ctx->>'partner_id')::uuid;
  v_all boolean := false;
  v_branches jsonb := '[]'::jsonb;
  v_branch_codes text[] := '{}'::text[];
  v_branch_names text[] := '{}'::text[];
begin
  select coalesce(s.all_branches,false) into v_all from public.partner_claim_settings s where s.partner_id=v_partner;
  if not found then v_all:=false; end if;
  select
    coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
    coalesce(array_agg(b.branch_code order by b.branch_name),'{}'::text[]),
    coalesce(array_agg(b.branch_name order by b.branch_name),'{}'::text[])
  into v_branches,v_branch_codes,v_branch_names
  from public.partner_claim_branches pcb
  join public.branches b on b.id=pcb.branch_id
  where pcb.partner_id=v_partner and b.status='active';
  return jsonb_build_object('success',true,'partner_id',v_partner,'all_branches',v_all,'branch_codes',v_branch_codes,'branch_names',v_branch_names,'branches',v_branches);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_partner_dashboard(p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_role text := v_ctx->>'role';
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,
    'partner_code',p.partner_code,
    'partner_name',p.partner_name,
    'voucher_limit',p.voucher_limit,
    'voucher_limit_unlimited',p.voucher_limit=0,
    'vouchers_issued',(select count(*) from public.vouchers v where v.partner_id=p.id),
    'remaining',case when p.voucher_limit=0 then null else greatest(0,p.voucher_limit-(select count(*) from public.vouchers v where v.partner_id=p.id)) end,
    'partner_status',p.status,
    'role',v_role,
    'staff_name',v_ctx->>'actor_name',
    'staff_access_enabled',p.staff_access_enabled,
    'staff_limit',p.staff_limit,
    'can_issue_voucher',case when v_role in ('partner_admin','admin') then true when v_role='partner_staff' then p.staff_access_enabled else false end,
    'admin_context',coalesce((v_ctx->>'is_admin')::boolean,false)
  ) into v_result
  from public.partners p
  where p.id=v_partner_id and p.status='active';
  if v_result is null then raise exception 'Active Partner not found'; end if;
  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.partner_issuable_voucher_catalog(p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(version_id uuid, template_id uuid, template_code text, template_name text, version_no integer, version_name text, voucher_label text, face_value numeric, discount_percent numeric, validity_mode text, valid_days integer, valid_months integer, valid_until date, usage_limit integer, transferable boolean, terms_text text, remaining_allocation bigint, remaining_supply bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_role text := v_ctx->>'role';
  v_staff_access_enabled boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select p.staff_access_enabled into v_staff_access_enabled
  from public.partners p
  where p.id=v_partner_id and p.status='active';
  if not found then raise exception 'Active Partner not found'; end if;
  if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;

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
    end,
    vv.face_value,
    vv.discount_percent,
    case
      when next_alloc.validity_anchor='allocation' and next_alloc.valid_until is not null then 'fixed'
      when next_alloc.validity_anchor='issue' and next_alloc.validity_unit in ('days','months') and next_alloc.validity_value is not null then next_alloc.validity_unit
      else vv.validity_mode
    end::text as validity_mode,
    case
      when next_alloc.validity_anchor='issue' and next_alloc.validity_unit='days' and next_alloc.validity_value is not null then next_alloc.validity_value
      when next_alloc.validity_anchor='allocation' then null
      else vv.valid_days
    end::integer as valid_days,
    case
      when next_alloc.validity_anchor='issue' and next_alloc.validity_unit='months' and next_alloc.validity_value is not null then next_alloc.validity_value
      when next_alloc.validity_anchor='allocation' then null
      else vv.valid_months
    end::integer as valid_months,
    case
      when next_alloc.validity_anchor='allocation' and next_alloc.valid_until is not null then (next_alloc.valid_until at time zone 'Asia/Kuala_Lumpur')::date
      when next_alloc.validity_anchor='issue' and next_alloc.validity_value is not null then null
      else vv.valid_until
    end::date as valid_until,
    vv.usage_limit,
    vv.transferable,
    vv.terms_text,
    alloc.remaining_allocation,
    case
      when vv.supply_limit is null then null
      else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint
    end
  from public.voucher_versions vv
  join public.voucher_templates vt
    on vt.id=vv.template_id and vt.status='active'
  join public.partner_voucher_access pva
    on pva.partner_id=v_partner_id
   and pva.template_id=vv.template_id
   and pva.status='active'
   and (pva.valid_from is null or pva.valid_from<=now())
   and (pva.valid_until is null or pva.valid_until>=now())
  join lateral (
    select coalesce(sum(greatest(0,(pa.quantity_allocated-pa.quantity_revoked)-coalesce(ai.issued_count,0))),0)::bigint as remaining_allocation
    from public.partner_voucher_allocations pa
    left join lateral (
      select count(*)::bigint as issued_count
      from public.vouchers vx
      where vx.allocation_id=pa.id
    ) ai on true
    where pa.partner_id=v_partner_id
      and pa.version_id=vv.id
      and pa.status='active'
      and (pa.valid_from is null or pa.valid_from<=now())
      and (pa.valid_until is null or pa.valid_until>=now())
  ) alloc on alloc.remaining_allocation>0
  join lateral (
    select pa.*
    from public.partner_voucher_allocations pa
    where pa.partner_id=v_partner_id
      and pa.version_id=vv.id
      and pa.status='active'
      and (pa.valid_from is null or pa.valid_from<=now())
      and (pa.valid_until is null or pa.valid_until>=now())
      and (pa.quantity_allocated-pa.quantity_revoked) > (
        select count(*) from public.vouchers vx where vx.allocation_id=pa.id
      )
    order by
      case when pa.validity_anchor='allocation' then 0 else 1 end,
      case when pa.validity_anchor='allocation' then pa.valid_until end asc nulls last,
      pa.created_at asc
    limit 1
  ) next_alloc on true
  left join lateral (
    select count(*)::bigint as issued_count
    from public.vouchers vx
    where vx.version_id=vv.id
  ) vi on true
  where vv.status='active'
    and (vv.validity_mode<>'fixed' or ((vv.valid_from is null or vv.valid_from<=v_today) and vv.valid_until is not null and vv.valid_until>=v_today))
    and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
  order by vt.template_name,vv.version_no desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.partner_recent_vouchers(p_limit integer DEFAULT 50, p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(voucher_id uuid, voucher_code text, customer_name text, customer_phone text, voucher_type text, voucher_status text, expiry_date date, issued_at timestamp with time zone, issued_by_name text, usage_count integer, usage_limit integer, last_redeemed_at timestamp with time zone, last_branch_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
begin
  if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500'; end if;
  return query
  select v.id,v.voucher_code,v.customer_name,v.customer_phone,v.voucher_type,
    case when v.status='revoked' then 'revoked' when v.status='expired' or (v.status='active' and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired' when v.usage_count>=v.usage_limit then 'redeemed' else 'active' end,
    v.expiry_date,v.issued_at,v.issued_by_name,v.usage_count,v.usage_limit,lr.redeemed_at,lr.branch_name
  from public.vouchers v
  left join lateral (
    select r.redeemed_at,b.branch_name
    from public.redemptions r join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id and r.status='completed'
    order by r.redeemed_at desc limit 1
  ) lr on true
  where v.partner_id=v_partner_id
  order by v.issued_at desc
  limit p_limit;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.partner_voucher_summary(p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ctx jsonb := public.resolve_partner_portal_context(p_partner_id);
  v_partner_id uuid := (v_ctx->>'partner_id')::uuid;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',v_partner_id,
    'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
    'active_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='active' and v.expiry_date>=v_today and v.usage_count<v.usage_limit),
    'redeemed_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and not (v.status='expired' or (v.status='active' and v.expiry_date<v_today)) and v.usage_count>=v.usage_limit),
    'expired_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status<>'revoked' and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))),
    'revoked_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='revoked'),
    'completed_redemptions',(select count(*) from public.redemptions r where r.partner_id=v_partner_id and r.status='completed')
  ) into v_result;
  return v_result;
end;
$function$
;
-- Align execute ACLs with Production.
revoke all on function public.partner_voucher_summary(uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_voucher_summary(uuid) to authenticated;

revoke all on function public.get_my_partner_dashboard(uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_my_partner_dashboard(uuid) to authenticated;

revoke all on function public.get_my_partner_claim_access(uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_my_partner_claim_access(uuid) to authenticated;

revoke all on function public.partner_recent_vouchers(integer,uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_recent_vouchers(integer,uuid) to authenticated;

revoke all on function public.partner_issuable_voucher_catalog(uuid) from public, anon, authenticated, service_role;
grant execute on function public.partner_issuable_voucher_catalog(uuid) to authenticated;
