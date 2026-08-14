-- Scoped reporting RPCs v1
-- Purpose: keep Partner and Staff UI from reading broad tables directly.
-- Admin reporting remains in 015; this migration adds tenant-safe operational views.

create or replace function public.partner_voucher_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id uuid := public.current_partner_id();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_result jsonb;
begin
  if v_partner_id is null then
    raise exception 'Active Partner account not found';
  end if;

  select jsonb_build_object(
    'partner_id',v_partner_id,
    'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
    'active_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='active' and v.expiry_date>=v_today and v.usage_count<v.usage_limit),
    'redeemed_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.usage_count>=v.usage_limit),
    'expired_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))),
    'revoked_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id and v.status='revoked'),
    'completed_redemptions',(select count(*) from public.redemptions r where r.partner_id=v_partner_id and r.status='completed')
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.partner_voucher_summary() from public, anon;
grant execute on function public.partner_voucher_summary() to authenticated;

create or replace function public.partner_recent_vouchers(p_limit integer default 50)
returns table(
  voucher_id uuid,
  voucher_code text,
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
  last_branch_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id uuid := public.current_partner_id();
begin
  if v_partner_id is null then
    raise exception 'Active Partner account not found';
  end if;
  if p_limit is null or p_limit<1 or p_limit>500 then
    raise exception 'Limit must be between 1 and 500';
  end if;

  return query
  select
    v.id,
    v.voucher_code,
    v.customer_name,
    v.customer_phone,
    v.voucher_type,
    case
      when v.status='revoked' then 'revoked'
      when v.status='expired' or (v.status='active' and v.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date) then 'expired'
      when v.usage_count>=v.usage_limit then 'redeemed'
      else 'active'
    end,
    v.expiry_date,
    v.issued_at,
    v.issued_by_name,
    v.usage_count,
    v.usage_limit,
    lr.redeemed_at,
    lr.branch_name
  from public.vouchers v
  left join lateral (
    select r.redeemed_at,b.branch_name
    from public.redemptions r
    join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id and r.status='completed'
    order by r.redeemed_at desc
    limit 1
  ) lr on true
  where v.partner_id=v_partner_id
  order by v.issued_at desc
  limit p_limit;
end;
$$;
revoke all on function public.partner_recent_vouchers(integer) from public, anon;
grant execute on function public.partner_recent_vouchers(integer) to authenticated;

create or replace function public.staff_recent_redemptions(p_limit integer default 20)
returns table(
  redemption_id uuid,
  voucher_id uuid,
  voucher_code text,
  customer_name text,
  voucher_type text,
  partner_name text,
  branch_id uuid,
  branch_name text,
  staff_name text,
  redeem_method text,
  redemption_status text,
  redeemed_at timestamptz,
  notes text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Limit must be between 1 and 100'; end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid and su.status='active'
  limit 1;
  if not found then raise exception 'Active Staff account not found'; end if;

  return query
  select
    r.id,
    r.voucher_id,
    v.voucher_code,
    v.customer_name,
    v.voucher_type,
    p.partner_name,
    r.branch_id,
    b.branch_name,
    r.staff_name_snapshot,
    r.redeem_method,
    r.status,
    r.redeemed_at,
    r.notes
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  join public.partners p on p.id=r.partner_id
  join public.branches b on b.id=r.branch_id
  where
    (v_staff.role='all_branch_manager')
    or (v_staff.role='manager' and r.branch_id=v_staff.branch_id)
    or (v_staff.role='staff' and r.staff_user_id=v_uid)
  order by r.redeemed_at desc
  limit p_limit;
end;
$$;
revoke all on function public.staff_recent_redemptions(integer) from public, anon;
grant execute on function public.staff_recent_redemptions(integer) to authenticated;

create or replace function public.staff_today_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_count bigint;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid and su.status='active'
  limit 1;
  if not found then raise exception 'Active Staff account not found'; end if;

  select count(*) into v_count
  from public.redemptions r
  where r.status='completed'
    and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
    and (
      v_staff.role='all_branch_manager'
      or (v_staff.role='manager' and r.branch_id=v_staff.branch_id)
      or (v_staff.role='staff' and r.staff_user_id=v_uid)
    );

  return jsonb_build_object(
    'success',true,
    'staff_user_id',v_uid,
    'staff_name',v_staff.staff_name,
    'role',v_staff.role,
    'branch_id',v_staff.branch_id,
    'today_redeemed',v_count
  );
end;
$$;
revoke all on function public.staff_today_summary() from public, anon;
grant execute on function public.staff_today_summary() to authenticated;
