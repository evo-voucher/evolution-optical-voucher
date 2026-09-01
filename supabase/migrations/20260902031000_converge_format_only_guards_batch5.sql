-- Converge remaining format-only trigger helper definitions on voucher-stage to current Production.
-- Exact signatures only. Production remains read-only.

CREATE OR REPLACE FUNCTION public.guard_partner_global_voucher_quota()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
declare v_limit integer; v_issued bigint;
begin
  if new.partner_id is null then raise exception 'Voucher partner_id is required'; end if;
  select p.voucher_limit into v_limit from public.partners p where p.id=new.partner_id and p.status='active' for update;
  if not found then raise exception 'Active Partner not found'; end if;
  if v_limit=0 then return new; end if;
  select count(*) into v_issued from public.vouchers v where v.partner_id=new.partner_id;
  if v_issued >= v_limit then raise exception 'Partner voucher limit reached'; end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION public.guard_partner_global_voucher_quota() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guard_partner_global_voucher_quota() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_partner_global_voucher_quota() FROM service_role;

CREATE OR REPLACE FUNCTION public.guard_voucher_immutable_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
declare
  v_reversal_allowed boolean := coalesce(current_setting('evo.reversal_allowed', true),'off') = 'on';
  v_reversal_voucher_id text := current_setting('evo.reversal_voucher_id', true);
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
    if not v_reversal_allowed or v_reversal_voucher_id is distinct from old.id::text then
      raise exception 'Voucher usage_count cannot decrease outside a controlled reversal';
    end if;
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION public.guard_voucher_immutable_identity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_immutable_identity() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_voucher_immutable_identity() FROM service_role;
