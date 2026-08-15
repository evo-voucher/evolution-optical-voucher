-- Voucher delivery policy snapshots v1
-- Freeze customer-facing presentation and validity policy at issuance time.

alter table public.voucher_versions
  add column if not exists greeting_text text;

alter table public.partner_voucher_allocations
  add column if not exists validity_anchor text not null default 'issue'
    check (validity_anchor in ('issue','allocation')),
  add column if not exists allocation_valid_days integer
    check (allocation_valid_days is null or allocation_valid_days > 0);

alter table public.vouchers
  add column if not exists validity_anchor_snapshot text,
  add column if not exists validity_value_snapshot integer,
  add column if not exists validity_unit_snapshot text,
  add column if not exists theme_code_snapshot text,
  add column if not exists theme_config_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists greeting_snapshot text,
  add column if not exists terms_snapshot text;

create or replace function public.snapshot_voucher_delivery_policy()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_version public.voucher_versions%rowtype;
  v_template public.voucher_templates%rowtype;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_theme_code text;
  v_theme_config jsonb;
  v_greeting text := E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.';
begin
  if new.version_id is null then
    return new;
  end if;

  select * into v_version from public.voucher_versions where id=new.version_id;
  if not found then raise exception 'Voucher Version does not exist'; end if;

  select * into v_template from public.voucher_templates where id=v_version.template_id;
  if not found then raise exception 'Voucher Template does not exist'; end if;

  if new.allocation_id is not null then
    select * into v_allocation
    from public.partner_voucher_allocations
    where id=new.allocation_id
      and partner_id=new.partner_id
      and version_id=new.version_id;
    if not found then raise exception 'Voucher Allocation does not match Partner and Version'; end if;
  end if;

  v_theme_code := coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default');
  v_theme_config := case
    when v_version.theme_override_code is not null then coalesce(v_version.theme_override_config,'{}'::jsonb)
    else coalesce(v_template.theme_config,'{}'::jsonb)
  end;

  new.theme_code_snapshot := v_theme_code;
  new.theme_config_snapshot := v_theme_config;
  new.greeting_snapshot := coalesce(nullif(trim(v_version.greeting_text),''),v_greeting);
  new.terms_snapshot := v_version.terms_text;

  if new.allocation_id is not null and v_allocation.validity_anchor='allocation' then
    if v_allocation.allocation_valid_days is null or v_allocation.valid_until is null then
      raise exception 'Allocation-anchored validity is not fully configured';
    end if;
    if v_allocation.valid_until < now() then
      raise exception 'Voucher Allocation validity has expired';
    end if;
    new.validity_anchor_snapshot := 'allocation';
    new.validity_value_snapshot := v_allocation.allocation_valid_days;
    new.validity_unit_snapshot := 'days';
    new.expiry_date := (v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
  else
    new.validity_anchor_snapshot := 'issue';
    if v_version.validity_mode='months' then
      new.validity_value_snapshot := v_version.valid_months;
      new.validity_unit_snapshot := 'months';
    elsif v_version.validity_mode='days' then
      new.validity_value_snapshot := v_version.valid_days;
      new.validity_unit_snapshot := 'days';
    else
      new.validity_value_snapshot := null;
      new.validity_unit_snapshot := 'fixed';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists vouchers_snapshot_delivery_policy on public.vouchers;
create trigger vouchers_snapshot_delivery_policy
before insert on public.vouchers
for each row execute function public.snapshot_voucher_delivery_policy();

create or replace function public.guard_voucher_delivery_snapshot_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.validity_anchor_snapshot is distinct from new.validity_anchor_snapshot
     or old.validity_value_snapshot is distinct from new.validity_value_snapshot
     or old.validity_unit_snapshot is distinct from new.validity_unit_snapshot
     or old.theme_code_snapshot is distinct from new.theme_code_snapshot
     or old.theme_config_snapshot is distinct from new.theme_config_snapshot
     or old.greeting_snapshot is distinct from new.greeting_snapshot
     or old.terms_snapshot is distinct from new.terms_snapshot then
    raise exception 'Issued Voucher delivery snapshot is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists vouchers_guard_delivery_snapshot_immutable on public.vouchers;
create trigger vouchers_guard_delivery_snapshot_immutable
before update on public.vouchers
for each row execute function public.guard_voucher_delivery_snapshot_immutable();

create or replace function public.get_public_voucher(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'success',true,
    'voucher_code',v.voucher_code,
    'voucher_type',v.voucher_type,
    'customer_name',v.customer_name,
    'partner_name',p.partner_name,
    'expiry_date',v.expiry_date,
    'status',case
      when v.status='redeemed' then 'redeemed'
      when v.status='revoked' then 'revoked'
      when v.status='expired' then 'expired'
      when v.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
      when v.status='active' then 'valid'
      else v.status
    end,
    'canonical_status',v.status,
    'issued_at',v.issued_at,
    'all_branches',v.all_branches,
    'validity_anchor',v.validity_anchor_snapshot,
    'validity_value',v.validity_value_snapshot,
    'validity_unit',v.validity_unit_snapshot,
    'theme_code',coalesce(v.theme_code_snapshot,'default'),
    'theme_config',coalesce(v.theme_config_snapshot,'{}'::jsonb),
    'greeting',coalesce(nullif(v.greeting_snapshot,''),E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.'),
    'terms_text',v.terms_snapshot,
    'branches',coalesce(
      case when v.all_branches then (
        select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
        from public.branches b where b.status='active'
      ) else (
        select jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name)
        from public.voucher_branches vb join public.branches b on b.id=vb.branch_id
        where vb.voucher_id=v.id and b.status='active'
      ) end,
      '[]'::jsonb
    )
  ) into v_result
  from public.vouchers v
  join public.partners p on p.id=v.partner_id
  where v.public_token=p_token
  limit 1;

  if v_result is null then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  return v_result;
end;
$$;

revoke all on function public.get_public_voucher(uuid) from public;
grant execute on function public.get_public_voucher(uuid) to anon, authenticated;

comment on function public.snapshot_voucher_delivery_policy() is
'Freezes validity basis, theme, greeting and terms on the issued Voucher so later design/rule edits cannot rewrite customer history.';
