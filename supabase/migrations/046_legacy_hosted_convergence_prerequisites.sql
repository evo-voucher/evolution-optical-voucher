-- Legacy hosted convergence prerequisites
-- Purpose: bridge the historical hosted Voucher schema to the current canonical lineage
-- without deleting or rewriting existing operational records.
-- Safe on canonical rebuilds: all structural changes are additive/idempotent.

alter table public.voucher_versions
  add column if not exists validity_mode text;

-- Historical hosted environments used validity_mode_v2 / validity_type.
-- Canonical runtime uses validity_mode values: days | months | fixed.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='voucher_versions' and column_name='validity_mode_v2'
  ) then
    execute $sql$
      update public.voucher_versions
      set validity_mode = case lower(trim(coalesce(validity_mode_v2,'')))
        when 'days_after_issue' then 'days'
        when 'days' then 'days'
        when 'calendar_months_after_issue' then 'months'
        when 'months' then 'months'
        when 'fixed' then 'fixed'
        else validity_mode
      end
      where validity_mode is null
        and nullif(trim(coalesce(validity_mode_v2,'')),'') is not null
    $sql$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='voucher_versions' and column_name='validity_type'
  ) then
    execute $sql$
      update public.voucher_versions
      set validity_mode = case lower(trim(coalesce(validity_type,'')))
        when 'days_after_issue' then 'days'
        when 'days' then 'days'
        when 'calendar_months_after_issue' then 'months'
        when 'months' then 'months'
        when 'fixed' then 'fixed'
        else validity_mode
      end
      where validity_mode is null
        and nullif(trim(coalesce(validity_type,'')),'') is not null
    $sql$;
  end if;
end
$$;

-- Existing allocations in the historical hosted project predate allocation-relative
-- validity and allocation-level branch scope. Preserve their old semantics:
-- issue-anchored validity and unrestricted allocation branch scope.
alter table public.partner_voucher_allocations
  add column if not exists validity_anchor text not null default 'issue',
  add column if not exists allocation_valid_days integer;

update public.partner_voucher_allocations
set validity_anchor='issue'
where validity_anchor is null or validity_anchor not in ('issue','allocation');

comment on column public.voucher_versions.validity_mode is
'Canonical validity mode used by current Voucher runtime. Legacy hosted values are converged additively from validity_mode_v2 / validity_type.';
