-- Remove the obsolete hard-coded district constraint.
-- Active district validation is now enforced by issue_engine_voucher_with_customer()
-- against public.customer_districts, which is the canonical source of truth.

alter table public.partner_customers
  drop constraint if exists partner_customers_district_allowed;
