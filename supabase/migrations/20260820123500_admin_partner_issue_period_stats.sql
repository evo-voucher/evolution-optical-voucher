-- Read-only Partner issue period statistics for Admin Dashboard.
-- Malaysia calendar boundaries: Today / current ISO week / current month.
-- No voucher issuance, redemption, allocation, or table mutation logic is changed.

create or replace function public.admin_partner_issue_period_stats()
returns table(
  partner_id uuid,
  partner_name text,
  voucher_type text,
  issued_today bigint,
  issued_week bigint,
  issued_month bigint
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_local_now timestamp := now() at time zone 'Asia/Kuala_Lumpur';
  v_day_start timestamptz := date_trunc('day', v_local_now) at time zone 'Asia/Kuala_Lumpur';
  v_week_start timestamptz := date_trunc('week', v_local_now) at time zone 'Asia/Kuala_Lumpur';
  v_month_start timestamptz := date_trunc('month', v_local_now) at time zone 'Asia/Kuala_Lumpur';
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    v.partner_id,
    p.partner_name,
    coalesce(nullif(trim(vt.template_name),''),'Unspecified') as voucher_type,
    count(*) filter (where v.issued_at >= v_day_start)::bigint as issued_today,
    count(*) filter (where v.issued_at >= v_week_start)::bigint as issued_week,
    count(*) filter (where v.issued_at >= v_month_start)::bigint as issued_month
  from public.vouchers v
  join public.partners p on p.id = v.partner_id
  join public.voucher_versions vv on vv.id = v.version_id
  join public.voucher_templates vt on vt.id = vv.template_id
  where v.issued_at is not null
    and v.issued_at >= least(v_week_start, v_month_start)
    and upper(coalesce(p.partner_code,'')) <> 'ADMIN'
    and lower(coalesce(p.status,'')) <> 'archived'
  group by v.partner_id, p.partner_name, coalesce(nullif(trim(vt.template_name),''),'Unspecified')
  having count(*) filter (where v.issued_at >= v_week_start or v.issued_at >= v_month_start) > 0
  order by p.partner_name, voucher_type;
end;
$function$;

revoke all on function public.admin_partner_issue_period_stats() from public;
revoke all on function public.admin_partner_issue_period_stats() from anon;
revoke all on function public.admin_partner_issue_period_stats() from authenticated;
grant execute on function public.admin_partner_issue_period_stats() to authenticated;
