-- Converge Customer / District schema with the current production baseline.
-- Production is read-only reference. Do not copy environment-specific row UUIDs.

alter table public.partner_customers
  add column if not exists birth_date date,
  add column if not exists district text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'partner_customers_birth_date_not_future'
      and conrelid = 'public.partner_customers'::regclass
  ) then
    alter table public.partner_customers
      add constraint partner_customers_birth_date_not_future
      check (birth_date is null or birth_date <= (now() at time zone 'Asia/Kuala_Lumpur')::date)
      not valid;
  end if;
end $$;

create table if not exists public.customer_districts (
  id uuid primary key default gen_random_uuid(),
  district_name text not null unique,
  sort_order integer not null unique,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null
);

alter table public.customer_districts enable row level security;
revoke all on table public.customer_districts from public, anon, authenticated;
grant all on table public.customer_districts to service_role;

create table if not exists public.system_customer_field_settings (
  singleton_id smallint primary key default 1 check (singleton_id = 1),
  phone_required boolean not null default false,
  birthday_required boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null,
  district_required boolean not null default false
);

alter table public.system_customer_field_settings enable row level security;
revoke all on table public.system_customer_field_settings from public, anon, authenticated;
grant all on table public.system_customer_field_settings to service_role;

insert into public.system_customer_field_settings (
  singleton_id, phone_required, birthday_required, district_required, updated_by
)
values (1, true, false, true, null)
on conflict (singleton_id) do update
set phone_required = excluded.phone_required,
    birthday_required = excluded.birthday_required,
    district_required = excluded.district_required,
    updated_at = now(),
    updated_by = null;

insert into public.customer_districts (district_name, sort_order, status, created_by)
values
  ('Kuala Lumpur', 1, 'active', null),
  ('Seri Kembangan', 2, 'active', null),
  ('Kajang', 3, 'active', null),
  ('Bangi', 4, 'active', null),
  ('Semenyih', 5, 'active', null),
  ('Hulu Langat', 6, 'active', null),
  ('Petaling', 7, 'active', null),
  ('Klang', 8, 'active', null),
  ('Gombak', 9, 'active', null),
  ('Sepang', 10, 'active', null),
  ('Kuala Selangor', 11, 'active', null),
  ('Kuala Langat', 12, 'active', null),
  ('Hulu Selangor', 13, 'active', null),
  ('Sabak Bernam', 14, 'active', null)
on conflict (district_name) do update
set sort_order = excluded.sort_order,
    status = excluded.status,
    updated_at = now();
