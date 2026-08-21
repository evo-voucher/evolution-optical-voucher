-- Admin Voucher Report display identity.
-- Presentation/read-model only: preserve Voucher, redemption and allocation records.
-- Keeps the existing admin_voucher_report() contract while returning a clearer
-- voucher_type display value: CODE · Classification · Amount.
-- Historical-safe sources are preferred where available:
--   code           -> Voucher metadata snapshot, then Template code fallback
--   classification -> Voucher theme snapshot, then Version/Template theme fallback
--   amount         -> immutable Voucher Version face value / discount

create or replace function public.admin_voucher_report(
  p_partner_id uuid default null,
  p_limit integer default 500
)
returns table(
  voucher_id uuid,
  voucher_code text,
  partner_id uuid,
  partner_name text,
  customer_name text,
  customer_phone text,
  voucher_type text,
  voucher_status text,
  expiry_date date,
  issued_at timestamptz,
  issued_by_name text,
  usage_count integer,
  usage_limit integer,
  last_redeemed_at timestamptz,
  last_branch_name text,
  last_staff_name text,
  completed_redemptions bigint,
  reversed_redemptions bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Limit must be between 1 and 5000';
  end if;

  return query
  select
    v.id,
    v.voucher_code,
    v.partner_id,
    p.partner_name,
    v.customer_name,
    v.customer_phone,
    concat_ws(
      ' · ',
      coalesce(nullif(v.metadata->>'template_code',''),vt.template_code,'—'),
      initcap(replace(coalesce(
        nullif(v.theme_code_snapshot,''),
        nullif(vv.theme_override_code,''),
        nullif(vt.theme_code,''),
        'custom'
      ),'_',' ')),
      case
        when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))
        when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'%'
        else coalesce(nullif(v.voucher_type,''),'—')
      end
    )::text as voucher_type,
    case
      when v.status='revoked' then 'revoked'
      when v.status='expired' or (v.status='active' and v.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired'
      when v.usage_count >= v.usage_limit then 'redeemed'
      else 'active'
    end as voucher_status,
    v.expiry_date,
    v.issued_at,
    v.issued_by_name,
    v.usage_count,
    v.usage_limit,
    lr.redeemed_at,
    lr.branch_name,
    lr.staff_name_snapshot,
    coalesce(rc.completed_count,0),
    coalesce(rc.reversed_count,0)
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  left join public.voucher_templates vt on vt.id=v.template_id
  left join public.voucher_versions vv on vv.id=v.version_id
  left join lateral (
    select r.redeemed_at,b.branch_name,r.staff_name_snapshot
    from public.redemptions r
    join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id
      and r.status='completed'
    order by r.redeemed_at desc
    limit 1
  ) lr on true
  left join lateral (
    select
      count(*) filter (where r.status='completed')::bigint as completed_count,
      count(*) filter (where r.status='reversed')::bigint as reversed_count
    from public.redemptions r
    where r.voucher_id=v.id
  ) rc on true
  where p_partner_id is null or v.partner_id=p_partner_id
  order by v.issued_at desc
  limit p_limit;
end;
$$;

revoke all on function public.admin_voucher_report(uuid,integer) from public, anon;
grant execute on function public.admin_voucher_report(uuid,integer) to authenticated;
