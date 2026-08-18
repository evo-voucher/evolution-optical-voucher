-- Read-only UAT checks for admin voucher reporting.
-- Run after applying 20260819012500_admin_voucher_reporting_v1.sql in a non-production environment.

-- 1) System-level invariant: allocated - issued = remaining.
with s as (
  select public.admin_dashboard_summary() as j
)
select
  (j->>'vouchers_allocated')::bigint as allocated,
  (j->>'vouchers_issued')::bigint as issued,
  (j->>'allocation_remaining')::bigint as remaining,
  ((j->>'vouchers_allocated')::bigint - (j->>'vouchers_issued')::bigint = (j->>'allocation_remaining')::bigint) as invariant_ok
from s;

-- 2) Every Partner must satisfy the same stock invariant.
select
  partner_id,
  vouchers_allocated,
  vouchers_issued,
  allocation_remaining,
  (vouchers_allocated - vouchers_issued = allocation_remaining) as invariant_ok
from public.admin_partner_reporting_summary()
order by partner_id;

-- 3) Voucher-type rows must satisfy allocated - issued = remaining.
select
  partner_id,
  partner_name,
  voucher_type,
  vouchers_allocated,
  vouchers_issued,
  allocation_remaining,
  (vouchers_allocated - vouchers_issued = allocation_remaining) as invariant_ok
from public.admin_voucher_type_summary(null)
order by partner_name,voucher_type;

-- 4) Cross-check system issued total against the Partner roll-up.
with s as (
  select (public.admin_dashboard_summary()->>'vouchers_issued')::bigint as system_issued
), p as (
  select coalesce(sum(vouchers_issued),0)::bigint as partner_issued
  from public.admin_partner_reporting_summary()
)
select s.system_issued,p.partner_issued,(s.system_issued=p.partner_issued) as totals_match
from s cross join p;

-- 5) Cross-check Partner issued total against voucher-type roll-up.
with p as (
  select partner_id,vouchers_issued
  from public.admin_partner_reporting_summary()
), t as (
  select partner_id,coalesce(sum(vouchers_issued),0)::bigint as type_issued
  from public.admin_voucher_type_summary(null)
  group by partner_id
)
select p.partner_id,p.vouchers_issued,coalesce(t.type_issued,0) as type_issued,
       (p.vouchers_issued=coalesce(t.type_issued,0)) as totals_match
from p left join t using(partner_id)
order by p.partner_id;
