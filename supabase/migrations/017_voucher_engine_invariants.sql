-- Voucher Engine invariants.
-- Published versions are immutable business snapshots.

create or replace function public.guard_published_voucher_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status='active' then
    if new.template_id is distinct from old.template_id
       or new.version_no is distinct from old.version_no
       or new.version_name is distinct from old.version_name
       or new.face_value is distinct from old.face_value
       or new.discount_percent is distinct from old.discount_percent
       or new.validity_mode is distinct from old.validity_mode
       or new.valid_days is distinct from old.valid_days
       or new.valid_months is distinct from old.valid_months
       or new.valid_from is distinct from old.valid_from
       or new.valid_until is distinct from old.valid_until
       or new.min_spend is distinct from old.min_spend
       or new.max_discount is distinct from old.max_discount
       or new.usage_limit is distinct from old.usage_limit
       or new.transferable is distinct from old.transferable
       or new.terms_text is distinct from old.terms_text
       or new.supply_limit is distinct from old.supply_limit
       or new.all_branches is distinct from old.all_branches
       or new.theme_override_code is distinct from old.theme_override_code
       or new.theme_override_config is distinct from old.theme_override_config
       or new.effective_from is distinct from old.effective_from
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'Published Voucher Version is immutable. Publish a new Version instead.';
    end if;

    if new.status not in ('active','inactive','archived') then
      raise exception 'Invalid Voucher Version status transition';
    end if;
  end if;
  return new;
end;
$$;

create trigger voucher_versions_guard_published
before update on public.voucher_versions
for each row execute function public.guard_published_voucher_version();

create or replace function public.guard_allocation_integrity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_issued integer;
begin
  select count(*) into v_issued
  from public.vouchers v
  where v.allocation_id=coalesce(new.id,old.id);

  if tg_op='UPDATE' then
    if new.partner_id is distinct from old.partner_id
       or new.version_id is distinct from old.version_id
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'Allocation identity fields are immutable';
    end if;

    if new.quantity_allocated < old.quantity_allocated then
      raise exception 'Allocated quantity cannot be reduced directly';
    end if;

    if new.quantity_revoked < old.quantity_revoked then
      raise exception 'Revoked quantity cannot be reduced directly';
    end if;
  end if;

  if new.quantity_revoked > new.quantity_allocated - v_issued then
    raise exception 'Cannot revoke quantity that has already been issued';
  end if;

  return new;
end;
$$;

create trigger partner_voucher_allocations_guard
before update on public.partner_voucher_allocations
for each row execute function public.guard_allocation_integrity();
