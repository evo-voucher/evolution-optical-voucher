-- Remove the obsolete hard-coded district constraint.
-- Active district validation is now enforced by issue_engine_voucher_with_customer()
-- against public.customer_districts, which is the canonical source of truth.
--
-- Fresh canonical rebuilds may reach this historical production hardening step
-- before partner_customers is introduced by the later customer-master migration.
-- In that case there is no legacy constraint to remove, so this is intentionally
-- a no-op. Existing hosted lineages that already have partner_customers still
-- receive the original constraint removal.

do $migration$
begin
  if to_regclass('public.partner_customers') is not null then
    alter table public.partner_customers
      drop constraint if exists partner_customers_district_allowed;
  end if;
end
$migration$;
