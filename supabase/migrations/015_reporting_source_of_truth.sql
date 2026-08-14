-- Canonical reporting layer.
-- Purpose: prevent UI counters from drifting away from actual redemption transactions.
-- Source of truth:
--   vouchers = issuance/state
--   redemptions = completed/reversed transaction history

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
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  select jsonb_build_object(
    'partners_total', (select count(*) from public.partners where status <> 'archived'),
    'partners_active', (select count(*) from public.partners where status = 'active'),
    'vouchers_total', (select count(*) from public.vouchers),
    'vouchers_active', (select count(*) from public.vouchers where status='active' and expiry_date >= v_today),
    'vouchers_redeemed', (select count(*) from public.vouchers where usage_count >= usage_limit and usage_limit > 0),
    'vouchers_expired', (select count(*) from public.vouchers where status='expired' or (status='active' and expiry_date < v_today)),
    'redemptions_completed', (select count(*) from public.redemptions where status='completed'),
    'redemptions_reversed', (select count(*) from public.redemptions where status='reversed'),
    'redemptions_today', (
      select count(*) from public.redemptions
      where status='completed'
        and (redeemed_at at time zone 'Asia/Kuala_Lumpur')::date = v_today
    )
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;

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
    v.voucher_type,
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

create or replace function public.admin_redemption_report(
  p_partner_id uuid default null,
  p_limit integer default 500
)
returns table(
  redemption_id uuid,
  voucher_id uuid,
  voucher_code text,
  partner_id uuid,
  partner_name text,
  branch_id uuid,
  branch_name text,
  staff_user_id uuid,
  staff_name text,
  redeem_method text,
  redemption_status text,
  redeemed_at timestamptz,
  notes text,
  reversed_at timestamptz,
  reversed_by_name text,
  reverse_reason text
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
    r.id,
    r.voucher_id,
    v.voucher_code,
    r.partner_id,
    p.partner_name,
    r.branch_id,
    b.branch_name,
    r.staff_user_id,
    r.staff_name_snapshot,
    r.redeem_method,
    r.status,
    r.redeemed_at,
    r.notes,
    r.reversed_at,
    r.reversed_by_name,
    r.reverse_reason
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  join public.partners p on p.id=r.partner_id
  join public.branches b on b.id=r.branch_id
  where p_partner_id is null or r.partner_id=p_partner_id
  order by r.redeemed_at desc
  limit p_limit;
end;
$$;
revoke all on function public.admin_redemption_report(uuid,integer) from public, anon;
grant execute on function public.admin_redemption_report(uuid,integer) to authenticated;
