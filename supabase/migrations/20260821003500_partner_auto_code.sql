begin;

create table if not exists public.partner_code_counters (
  prefix text primary key check (prefix ~ '^[A-Z]$'),
  last_number integer not null check (last_number between 0 and 999),
  updated_at timestamptz not null default now()
);

alter table public.partner_code_counters enable row level security;
revoke all on table public.partner_code_counters from anon, authenticated;

create or replace function public.admin_preview_partner_code(p_partner_name text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prefix text;
  v_existing_max integer := 0;
  v_counter integer := 0;
  v_next integer;
begin
  if not exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
      and au.status = 'active'
  ) then
    raise exception 'Admin access required';
  end if;

  v_prefix := upper(substring(coalesce(trim(p_partner_name), '') from '[A-Za-z]'));
  if v_prefix is null or v_prefix !~ '^[A-Z]$' then
    return null;
  end if;

  select coalesce(max(substring(p.partner_code from 2)::integer), 0)
    into v_existing_max
  from public.partners p
  where p.partner_code ~ ('^' || v_prefix || '[0-9]{3}$');

  select coalesce(c.last_number, 0)
    into v_counter
  from public.partner_code_counters c
  where c.prefix = v_prefix;

  v_next := greatest(v_existing_max, v_counter) + 1;
  if v_next > 999 then
    return null;
  end if;

  return v_prefix || lpad(v_next::text, 3, '0');
end;
$$;

create or replace function public.admin_next_partner_code(p_partner_name text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prefix text;
  v_existing_max integer := 0;
  v_next integer;
begin
  if not exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
      and au.status = 'active'
  ) then
    raise exception 'Admin access required';
  end if;

  v_prefix := upper(substring(coalesce(trim(p_partner_name), '') from '[A-Za-z]'));
  if v_prefix is null or v_prefix !~ '^[A-Z]$' then
    raise exception 'Partner Name must contain an A-Z letter';
  end if;

  select coalesce(max(substring(p.partner_code from 2)::integer), 0)
    into v_existing_max
  from public.partners p
  where p.partner_code ~ ('^' || v_prefix || '[0-9]{3}$');

  insert into public.partner_code_counters(prefix, last_number, updated_at)
  values (v_prefix, v_existing_max + 1, now())
  on conflict (prefix) do update
    set last_number = greatest(public.partner_code_counters.last_number + 1, excluded.last_number),
        updated_at = now()
  returning last_number into v_next;

  if v_next > 999 then
    raise exception 'Partner Code capacity reached for prefix %', v_prefix;
  end if;

  return v_prefix || lpad(v_next::text, 3, '0');
end;
$$;

revoke all on function public.admin_preview_partner_code(text) from public, anon;
revoke all on function public.admin_next_partner_code(text) from public, anon;
grant execute on function public.admin_preview_partner_code(text) to authenticated;
grant execute on function public.admin_next_partner_code(text) to authenticated;

commit;
