-- Customer master + safe voucher retention
-- Customer records are tenant-scoped by partner_id. A customer may own many vouchers.

create table if not exists public.partner_customers (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  customer_name text not null,
  customer_phone text,
  normalized_phone text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists partner_customers_partner_phone_uq
  on public.partner_customers(partner_id, normalized_phone)
  where normalized_phone is not null;

alter table public.partner_customers enable row level security;
revoke all on public.partner_customers from anon, authenticated;
grant select, insert, update, delete on public.partner_customers to service_role;

alter table public.vouchers
  add column if not exists customer_id uuid references public.partner_customers(id) on delete restrict;
create index if not exists vouchers_customer_id_idx on public.vouchers(customer_id);

create or replace function public.normalize_customer_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if v_digits='' then return null; end if;
  -- Malaysia-friendly canonicalisation: +60 / 60xxxxxxxxx -> 0xxxxxxxxx
  if v_digits like '60%' and length(v_digits) between 10 and 12 then
    return '0' || substring(v_digits from 3);
  end if;
  return v_digits;
end;
$function$;

create or replace function public.attach_voucher_customer()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_norm text;
  v_customer_id uuid;
begin
  if new.partner_id is null or nullif(trim(coalesce(new.customer_name,'')),'') is null then
    return new;
  end if;

  v_norm := public.normalize_customer_phone(new.customer_phone);

  if v_norm is not null then
    insert into public.partner_customers(
      partner_id,customer_name,customer_phone,normalized_phone,first_seen_at,last_seen_at,created_at,updated_at
    ) values (
      new.partner_id,trim(new.customer_name),nullif(trim(coalesce(new.customer_phone,'')),''),v_norm,
      coalesce(new.issued_at,now()),coalesce(new.issued_at,now()),now(),now()
    )
    on conflict (partner_id,normalized_phone) where normalized_phone is not null
    do update set
      customer_name=excluded.customer_name,
      customer_phone=excluded.customer_phone,
      last_seen_at=greatest(public.partner_customers.last_seen_at,excluded.last_seen_at),
      updated_at=now()
    returning id into v_customer_id;
  elsif new.customer_id is not null then
    update public.partner_customers
      set customer_name=trim(new.customer_name),
          customer_phone=nullif(trim(coalesce(new.customer_phone,'')),''),
          last_seen_at=greatest(last_seen_at,coalesce(new.issued_at,now())),
          updated_at=now()
      where id=new.customer_id and partner_id=new.partner_id
      returning id into v_customer_id;
  else
    -- Without a phone there is no safe automatic identity key; do not merge by name alone.
    insert into public.partner_customers(
      partner_id,customer_name,customer_phone,normalized_phone,first_seen_at,last_seen_at
    ) values (
      new.partner_id,trim(new.customer_name),nullif(trim(coalesce(new.customer_phone,'')),''),null,
      coalesce(new.issued_at,now()),coalesce(new.issued_at,now())
    ) returning id into v_customer_id;
  end if;

  new.customer_id := v_customer_id;
  return new;
end;
$function$;

drop trigger if exists trg_attach_voucher_customer on public.vouchers;
create trigger trg_attach_voucher_customer
before insert or update of partner_id,customer_name,customer_phone
on public.vouchers
for each row execute function public.attach_voucher_customer();

-- Backfill existing vouchers. Mentioning customer_name intentionally fires the trigger.
update public.vouchers
set customer_name=customer_name
where customer_id is null;

create or replace function public.purge_unredeemed_vouchers(p_retention_days integer default 30)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_deleted integer := 0;
begin
  if not public.is_trusted_service_role() then
    raise exception 'Trusted server context required';
  end if;
  if p_retention_days is null or p_retention_days < 1 or p_retention_days > 3650 then
    raise exception 'Retention days must be between 1 and 3650';
  end if;

  delete from public.vouchers v
  where coalesce(v.usage_count,0)=0
    and not exists (select 1 from public.redemptions r where r.voucher_id=v.id)
    and (
      (
        (v.status='revoked' or v.revoked_at is not null)
        and coalesce(v.revoked_at,v.updated_at,v.created_at) < now() - make_interval(days=>p_retention_days)
      )
      or
      (
        v.expiry_date is not null
        and v.expiry_date < ((now() at time zone 'Asia/Kuala_Lumpur')::date - p_retention_days)
      )
    );
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.purge_unredeemed_vouchers(integer) from public, anon, authenticated;
grant execute on function public.purge_unredeemed_vouchers(integer) to service_role;
