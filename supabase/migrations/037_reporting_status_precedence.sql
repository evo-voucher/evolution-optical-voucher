-- Reporting status precedence normalization v1
-- Canonical display precedence across Admin/Partner reports:
-- revoked > expired > redeemed > active.
-- Summary buckets must use the same precedence so counts do not overlap.

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
    'vouchers_active', (
      select count(*) from public.vouchers v
      where v.status='active'
        and v.expiry_date>=v_today
        and v.usage_count<v.usage_limit
    ),
    'vouchers_redeemed', (
      select count(*) from public.vouchers v
      where v.status<>'revoked'
        and not (v.status='expired' or (v.status='active' and v.expiry_date<v_today))
        and v.usage_count>=v.usage_limit
    ),
    'vouchers_expired', (
      select count(*) from public.vouchers v
      where v.status<>'revoked'
        and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))
    ),
    'vouchers_revoked', (select count(*) from public.vouchers v where v.status='revoked'),
    'redemptions_completed', (select count(*) from public.redemptions where status='completed'),
    'redemptions_reversed', (select count(*) from public.redemptions where status='reversed'),
    'redemptions_today', (
      select count(*) from public.redemptions
      where status='completed'
        and (redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
    )
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;

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
    'active_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and v.status='active'
        and v.expiry_date>=v_today
        and v.usage_count<v.usage_limit
    ),
    'redeemed_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and v.status<>'revoked'
        and not (v.status='expired' or (v.status='active' and v.expiry_date<v_today))
        and v.usage_count>=v.usage_limit
    ),
    'expired_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and v.status<>'revoked'
        and (v.status='expired' or (v.status='active' and v.expiry_date<v_today))
    ),
    'revoked_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id and v.status='revoked'
    ),
    'completed_redemptions',(
      select count(*) from public.redemptions r
      where r.partner_id=v_partner_id and r.status='completed'
    )
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.partner_voucher_summary() from public, anon;
grant execute on function public.partner_voucher_summary() to authenticated;

comment on function public.admin_dashboard_summary() is
'Canonical Admin summary. Voucher status buckets are mutually exclusive with precedence revoked > expired > redeemed > active.';
comment on function public.partner_voucher_summary() is
'Canonical Partner summary. Voucher status buckets are mutually exclusive with precedence revoked > expired > redeemed > active.';