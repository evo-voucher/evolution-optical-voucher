-- Admin Latest Activity read model.
-- Scope: read-only aggregation of existing Voucher, Redemption and Admin audit records.
-- No business writes, RLS policies, Voucher issuance, redemption, or historical rows are changed.

create or replace function public.admin_latest_activity(p_limit integer default 30)
returns table(
  event_id text,
  event_type text,
  event_time timestamptz,
  partner_id uuid,
  partner_name text,
  title text,
  detail text,
  voucher_id uuid,
  voucher_code text,
  branch_name text
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

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limit must be between 1 and 100';
  end if;

  return query
  select x.event_id,
         x.event_type,
         x.event_time,
         x.partner_id,
         x.partner_name,
         x.title,
         x.detail,
         x.voucher_id,
         x.voucher_code,
         x.branch_name
  from (
    select
      'voucher:' || v.id::text as event_id,
      'voucher_issued'::text as event_type,
      v.issued_at as event_time,
      v.partner_id,
      p.partner_name,
      (coalesce(nullif(p.partner_name,''),'Partner') || ' issued a voucher')::text as title,
      concat_ws(' · ',nullif(v.voucher_code,''),nullif(v.customer_name,''),nullif(v.voucher_type,''))::text as detail,
      v.id as voucher_id,
      v.voucher_code,
      null::text as branch_name
    from public.vouchers v
    left join public.partners p on p.id=v.partner_id
    where v.issued_at is not null

    union all

    select
      'redemption:' || r.id::text,
      case when lower(coalesce(r.status,''))='reversed' then 'redemption_reversed' else 'voucher_redeemed' end,
      case when lower(coalesce(r.status,''))='reversed' then coalesce(r.reversed_at,r.redeemed_at) else r.redeemed_at end,
      coalesce(r.partner_id,v.partner_id),
      p.partner_name,
      case
        when lower(coalesce(r.status,''))='reversed'
          then ('Redemption reversed · ' || coalesce(nullif(v.voucher_code,''),'Voucher'))::text
        else ('Voucher redeemed · ' || coalesce(nullif(v.voucher_code,''),'Voucher'))::text
      end,
      concat_ws(' · ',nullif(p.partner_name,''),nullif(b.branch_name,''),nullif(r.staff_name_snapshot,''))::text,
      v.id,
      v.voucher_code,
      b.branch_name
    from public.redemptions r
    join public.vouchers v on v.id=r.voucher_id
    left join public.partners p on p.id=coalesce(r.partner_id,v.partner_id)
    left join public.branches b on b.id=r.branch_id
    where r.redeemed_at is not null

    union all

    select
      'audit:' || a.id::text,
      a.action_type,
      a.created_at,
      a.partner_id,
      p.partner_name,
      case a.action_type
        when 'partner_status_changed' then (coalesce(nullif(p.partner_name,''),'Partner') || ' status changed')::text
        when 'partner_voucher_limit_changed' then (coalesce(nullif(p.partner_name,''),'Partner') || ' voucher limit updated')::text
        when 'partner_staff_limit_changed' then (coalesce(nullif(p.partner_name,''),'Partner') || ' staff limit updated')::text
        else initcap(replace(a.action_type,'_',' '))::text
      end,
      case a.action_type
        when 'partner_status_changed' then ('Status: ' || coalesce(a.after_data->>'status','updated'))::text
        when 'partner_voucher_limit_changed' then ('Limit: ' || coalesce(a.after_data->>'voucher_limit','updated'))::text
        when 'partner_staff_limit_changed' then ('Limit: ' || coalesce(a.after_data->>'staff_limit','updated'))::text
        else coalesce(nullif(a.actor_name,''),'Admin activity')::text
      end,
      null::uuid,
      null::text,
      null::text
    from public.admin_audit_log a
    left join public.partners p on p.id=a.partner_id
  ) x
  where x.event_time is not null
  order by x.event_time desc, x.event_id desc
  limit p_limit;
end;
$$;

revoke all on function public.admin_latest_activity(integer) from public, anon;
grant execute on function public.admin_latest_activity(integer) to authenticated;

comment on function public.admin_latest_activity(integer) is
'Admin-only read model combining recent voucher issuance, redemption, and Admin audit events into one time-ordered activity feed.';
