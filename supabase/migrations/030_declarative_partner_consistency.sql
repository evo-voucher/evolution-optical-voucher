-- Declarative Partner consistency v1
-- Purpose: enforce cross-Partner integrity with PostgreSQL foreign keys in addition
-- to trigger/RLS guards. These constraints are identity-independent and also apply
-- to trusted service_role server writes.

-- Referenced composite keys. PostgreSQL requires a UNIQUE/PK matching each
-- referenced FK column set exactly; the primary key on id alone is not sufficient
-- for foreign keys that reference (id, partner_id).
alter table public.partner_voucher_allocations
  add constraint partner_voucher_allocations_id_partner_uk
  unique (id, partner_id);

alter table public.partner_voucher_allocations
  add constraint partner_voucher_allocations_id_partner_version_uk
  unique (id, partner_id, version_id);

alter table public.vouchers
  add constraint vouchers_id_partner_uk
  unique (id, partner_id);

-- A Voucher allocation, when present, must belong to the same Partner as the Voucher.
alter table public.vouchers
  add constraint vouchers_allocation_partner_fk
  foreign key (allocation_id, partner_id)
  references public.partner_voucher_allocations(id, partner_id)
  on delete restrict;

-- A Redemption can never claim a different Partner than its Voucher.
alter table public.redemptions
  add constraint redemptions_voucher_partner_fk
  foreign key (voucher_id, partner_id)
  references public.vouchers(id, partner_id)
  on delete restrict;

-- Allocation-event tenant/version identity must exactly match its Allocation.
alter table public.voucher_allocation_events
  add constraint voucher_allocation_events_allocation_tenant_fk
  foreign key (allocation_id, partner_id, version_id)
  references public.partner_voucher_allocations(id, partner_id, version_id)
  on delete restrict;

comment on constraint vouchers_allocation_partner_fk on public.vouchers is
'Declarative tenant guard: Voucher allocation must belong to the Voucher Partner.';

comment on constraint redemptions_voucher_partner_fk on public.redemptions is
'Declarative tenant guard: Redemption Partner must equal Voucher Partner.';

comment on constraint voucher_allocation_events_allocation_tenant_fk on public.voucher_allocation_events is
'Declarative tenant guard: allocation event Partner and Version must equal its Allocation.';
