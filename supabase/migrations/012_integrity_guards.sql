-- Database integrity guards.
-- These triggers protect historical truth even when service-role code is used.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger partners_touch_updated_at
before update on public.partners
for each row execute function public.touch_updated_at();

create trigger branches_touch_updated_at
before update on public.branches
for each row execute function public.touch_updated_at();

create trigger partner_users_touch_updated_at
before update on public.partner_users
for each row execute function public.touch_updated_at();

create trigger staff_users_touch_updated_at
before update on public.staff_users
for each row execute function public.touch_updated_at();

create trigger vouchers_touch_updated_at
before update on public.vouchers
for each row execute function public.touch_updated_at();

create trigger admin_users_touch_updated_at
before update on public.admin_users
for each row execute function public.touch_updated_at();

create trigger voucher_templates_touch_updated_at
before update on public.voucher_templates
for each row execute function public.touch_updated_at();

create trigger partner_voucher_access_touch_updated_at
before update on public.partner_voucher_access
for each row execute function public.touch_updated_at();

create trigger partner_voucher_allocations_touch_updated_at
before update on public.partner_voucher_allocations
for each row execute function public.touch_updated_at();

create or replace function public.guard_voucher_immutable_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.voucher_code is distinct from old.voucher_code
     or new.public_token is distinct from old.public_token
     or new.partner_id is distinct from old.partner_id
     or new.issued_at is distinct from old.issued_at
     or new.issued_by_user_id is distinct from old.issued_by_user_id
     or new.template_id is distinct from old.template_id
     or new.version_id is distinct from old.version_id
     or new.allocation_id is distinct from old.allocation_id
     or new.usage_limit is distinct from old.usage_limit then
    raise exception 'Immutable voucher identity fields cannot be changed after issuance';
  end if;

  if new.usage_count < old.usage_count then
    -- Only a valid redemption reversal may reduce usage_count; the reversal RPC
    -- updates the redemption first, so verify a recent reversed row exists.
    if not exists (
      select 1 from public.redemptions r
      where r.voucher_id=old.id
        and r.status='reversed'
        and r.reversed_at is not null
        and r.reversed_at >= now() - interval '5 seconds'
    ) then
      raise exception 'Voucher usage_count cannot decrease outside a controlled reversal';
    end if;
  end if;

  return new;
end;
$$;

create trigger vouchers_guard_immutable_identity
before update on public.vouchers
for each row execute function public.guard_voucher_immutable_identity();

create or replace function public.guard_redemption_history()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op='DELETE' then
    raise exception 'Redemption history cannot be deleted';
  end if;

  if new.id is distinct from old.id
     or new.voucher_id is distinct from old.voucher_id
     or new.partner_id is distinct from old.partner_id
     or new.branch_id is distinct from old.branch_id
     or new.staff_user_id is distinct from old.staff_user_id
     or new.staff_name_snapshot is distinct from old.staff_name_snapshot
     or new.redeem_method is distinct from old.redeem_method
     or new.redeemed_at is distinct from old.redeemed_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Redemption identity/history fields are immutable';
  end if;

  if old.status='completed' and new.status='reversed' then
    if new.reversed_at is null or new.reversed_by_user_id is null or nullif(trim(coalesce(new.reverse_reason,'')),'') is null then
      raise exception 'Reversal audit fields are required';
    end if;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.reversed_at is distinct from old.reversed_at
     or new.reversed_by_user_id is distinct from old.reversed_by_user_id
     or new.reversed_by_name is distinct from old.reversed_by_name
     or new.reverse_reason is distinct from old.reverse_reason then
    raise exception 'Redemption can only transition from completed to reversed';
  end if;

  return new;
end;
$$;

create trigger redemptions_guard_update
before update on public.redemptions
for each row execute function public.guard_redemption_history();

create trigger redemptions_guard_delete
before delete on public.redemptions
for each row execute function public.guard_redemption_history();

create or replace function public.guard_audit_log_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Audit log is append-only';
end;
$$;

create trigger admin_audit_log_no_update
before update on public.admin_audit_log
for each row execute function public.guard_audit_log_immutable();

create trigger admin_audit_log_no_delete
before delete on public.admin_audit_log
for each row execute function public.guard_audit_log_immutable();
