-- Partner isolation declarative-constraint audit v1
-- Non-destructive. Run after migrations on the reconstructed target.
-- Every FAIL section must return zero rows.

-- A. Required tenant-consistency constraints must exist and be validated.
-- Expected: zero rows.
with required(table_name,constraint_name) as (
  values
    ('vouchers','vouchers_allocation_partner_fk'),
    ('redemptions','redemptions_voucher_partner_fk'),
    ('voucher_allocation_events','voucher_allocation_events_allocation_tenant_fk')
)
select r.table_name,r.constraint_name
from required r
left join pg_constraint c
  on c.conname=r.constraint_name
left join pg_class t
  on t.oid=c.conrelid and t.relname=r.table_name
left join pg_namespace n
  on n.oid=t.relnamespace and n.nspname='public'
where c.oid is null or n.oid is null or not c.convalidated
order by r.table_name;

-- B. Composite tenant identity keys required by the FKs must exist.
-- Expected: zero rows.
with required(constraint_name) as (
  values
    ('partner_voucher_allocations_id_partner_version_uk'),
    ('vouchers_id_partner_uk')
)
select r.constraint_name
from required r
left join pg_constraint c
  on c.conname=r.constraint_name
where c.oid is null or c.contype<>'u' or not c.convalidated
order by r.constraint_name;

-- C. Inventory the exact FK definitions for human review.
-- Expected references:
-- vouchers(allocation_id,partner_id) -> partner_voucher_allocations(id,partner_id)
-- redemptions(voucher_id,partner_id) -> vouchers(id,partner_id)
-- voucher_allocation_events(allocation_id,partner_id,version_id)
--   -> partner_voucher_allocations(id,partner_id,version_id)
select
  c.conname as constraint_name,
  pg_get_constraintdef(c.oid,true) as definition
from pg_constraint c
join pg_class t on t.oid=c.conrelid
join pg_namespace n on n.oid=t.relnamespace
where n.nspname='public'
  and c.conname in (
    'vouchers_allocation_partner_fk',
    'redemptions_voucher_partner_fk',
    'voucher_allocation_events_allocation_tenant_fk'
  )
order by c.conname;
