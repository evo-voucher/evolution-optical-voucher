-- Converge automatic Partner code assignment with Production.
-- Production remains read-only reference.

create or replace function public.assign_partner_code_before_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_initial text;
  v_next integer;
begin
  if upper(trim(coalesce(new.partner_code,''))) <> 'AUTO' then
    return new;
  end if;

  v_initial := upper(left(regexp_replace(coalesce(trim(new.partner_name), ''), '[^A-Za-z0-9]+', '', 'g'), 1));
  if v_initial is null or v_initial = '' or v_initial !~ '^[A-Z]$' then
    v_initial := 'P';
  end if;

  perform pg_advisory_xact_lock(hashtext('partner-code-' || v_initial));

  select coalesce(max((substring(partner_code from 2 for 3))::integer), 0) + 1
    into v_next
  from public.partners
  where partner_code ~ ('^' || v_initial || '[0-9]{3}$');

  if v_next > 999 then
    raise exception 'Partner code range exhausted for prefix %', v_initial;
  end if;

  new.partner_code := v_initial || lpad(v_next::text, 3, '0');
  return new;
end;
$function$;

revoke all on function public.assign_partner_code_before_insert() from public, anon, authenticated, service_role;

drop trigger if exists trg_assign_partner_code_before_insert on public.partners;
create trigger trg_assign_partner_code_before_insert
before insert on public.partners
for each row execute function public.assign_partner_code_before_insert();
