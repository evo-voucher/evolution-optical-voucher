-- Correct newline escaping in snapshot_voucher_delivery_policy() after PR #67.
-- Logic/ACL already match Production; only E-string newline escaping remains different.
-- Production remains read-only.

CREATE OR REPLACE FUNCTION public.snapshot_voucher_delivery_policy()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
declare
  v_version public.voucher_versions%rowtype;
  v_template public.voucher_templates%rowtype;
  v_allocation public.partner_voucher_allocations%rowtype;
  v_theme_code text;
  v_theme_config jsonb;
  v_default_greeting text := E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.';
  v_occasion text;
begin
  if new.version_id is null then return new; end if;

  select * into v_version from public.voucher_versions where id=new.version_id;
  if not found then raise exception 'Voucher Version does not exist'; end if;

  select * into v_template from public.voucher_templates where id=v_version.template_id;
  if not found then raise exception 'Voucher Template does not exist'; end if;

  if new.allocation_id is not null then
    select * into v_allocation
    from public.partner_voucher_allocations
    where id=new.allocation_id and partner_id=new.partner_id and version_id=new.version_id;
    if not found then raise exception 'Voucher Allocation does not match Partner and Version'; end if;
  end if;

  v_theme_code:=coalesce(nullif(v_version.theme_override_code,''),v_template.theme_code,'default');
  v_theme_config:=case
    when nullif(v_version.theme_override_code,'') is not null then coalesce(v_version.theme_override_config,'{}'::jsonb)
    else coalesce(v_template.theme_config,'{}'::jsonb)
  end;
  v_occasion:=nullif(trim(coalesce(v_version.greeting_text,'')),'');

  new.theme_code_snapshot:=v_theme_code;
  new.theme_config_snapshot:=v_theme_config;
  new.greeting_snapshot:=v_default_greeting||case when v_occasion is not null then E'\n'||v_occasion else '' end;
  new.terms_snapshot:=v_version.terms_text;

  if new.allocation_id is not null then
    if v_allocation.validity_anchor='allocation' then
      if v_allocation.valid_until is null then raise exception 'Allocation-anchored validity is not fully configured'; end if;
      if v_allocation.valid_until<now() then raise exception 'Voucher Allocation validity has expired'; end if;
      new.validity_anchor_snapshot:='allocation';
      if v_allocation.validity_value is not null and v_allocation.validity_unit in ('days','months') then
        new.validity_value_snapshot:=v_allocation.validity_value;
        new.validity_unit_snapshot:=v_allocation.validity_unit;
      else
        new.validity_value_snapshot:=v_allocation.allocation_valid_days;
        new.validity_unit_snapshot:='days';
      end if;
      new.expiry_date:=(v_allocation.valid_until at time zone 'Asia/Kuala_Lumpur')::date;
      return new;
    elsif v_allocation.validity_anchor='issue'
      and v_allocation.validity_value is not null
      and v_allocation.validity_unit in ('days','months') then
      new.validity_anchor_snapshot:='issue';
      new.validity_value_snapshot:=v_allocation.validity_value;
      new.validity_unit_snapshot:=v_allocation.validity_unit;
      return new;
    end if;
  end if;

  new.validity_anchor_snapshot:='issue';
  if v_version.validity_mode='months' then
    new.validity_value_snapshot:=v_version.valid_months;
    new.validity_unit_snapshot:='months';
  elsif v_version.validity_mode='days' then
    new.validity_value_snapshot:=v_version.valid_days;
    new.validity_unit_snapshot:='days';
  else
    new.validity_value_snapshot:=null;
    new.validity_unit_snapshot:='fixed';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION public.snapshot_voucher_delivery_policy() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.snapshot_voucher_delivery_policy() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.snapshot_voucher_delivery_policy() FROM service_role;
