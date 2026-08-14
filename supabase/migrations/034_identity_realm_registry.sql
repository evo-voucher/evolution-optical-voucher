-- Operational identity realm registry v1
-- Root-level invariant: one Auth identity may operate in only one live realm.
-- A single registry row provides a declarative cross-table serialization point,
-- avoiding race windows between admin_users / partner_users / staff_users.

create table if not exists public.operational_identity_realms (
  user_id uuid primary key references auth.users(id) on delete cascade,
  realm text not null check (realm in ('admin','partner','staff')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.operational_identity_realms enable row level security;
revoke all on public.operational_identity_realms from anon, authenticated;

-- Refuse migration if legacy data already violates the one-live-realm rule.
do $$
declare
  v_conflict uuid;
begin
  with live_realms as (
    select au.user_id,'admin'::text as realm
    from public.admin_users au
    where au.status='active'
    union all
    select pu.user_id,'partner'::text
    from public.partner_users pu
    where pu.status='active' and pu.removed_at is null
    union all
    select su.user_id,'staff'::text
    from public.staff_users su
    where su.status='active'
  )
  select lr.user_id into v_conflict
  from live_realms lr
  group by lr.user_id
  having count(distinct lr.realm)>1
  limit 1;

  if v_conflict is not null then
    raise exception 'Existing Auth identity belongs to more than one active operational realm: %',v_conflict;
  end if;
end;
$$;

-- Seed registry from existing valid live identities.
insert into public.operational_identity_realms(user_id,realm)
select au.user_id,'admin'
from public.admin_users au
where au.status='active'
on conflict(user_id) do update set realm=excluded.realm,updated_at=now()
where public.operational_identity_realms.realm=excluded.realm;

insert into public.operational_identity_realms(user_id,realm)
select pu.user_id,'partner'
from public.partner_users pu
where pu.status='active' and pu.removed_at is null
on conflict(user_id) do update set realm=excluded.realm,updated_at=now()
where public.operational_identity_realms.realm=excluded.realm;

insert into public.operational_identity_realms(user_id,realm)
select su.user_id,'staff'
from public.staff_users su
where su.status='active'
on conflict(user_id) do update set realm=excluded.realm,updated_at=now()
where public.operational_identity_realms.realm=excluded.realm;

create or replace function public.claim_operational_identity_realm(
  p_user_id uuid,
  p_realm text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed text;
begin
  if p_user_id is null then raise exception 'Auth user_id is required'; end if;
  if p_realm not in ('admin','partner','staff') then raise exception 'Invalid operational realm'; end if;

  insert into public.operational_identity_realms(user_id,realm)
  values(p_user_id,p_realm)
  on conflict(user_id) do update
    set updated_at=now()
    where public.operational_identity_realms.realm=excluded.realm
  returning realm into v_claimed;

  if v_claimed is null then
    raise exception 'Auth identity already belongs to a different active operational realm';
  end if;
end;
$$;
revoke all on function public.claim_operational_identity_realm(uuid,text) from public, anon, authenticated;
grant execute on function public.claim_operational_identity_realm(uuid,text) to service_role;

create or replace function public.release_operational_identity_realm(
  p_user_id uuid,
  p_realm text
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.operational_identity_realms r
  where r.user_id=p_user_id and r.realm=p_realm;
$$;
revoke all on function public.release_operational_identity_realm(uuid,text) from public, anon, authenticated;
grant execute on function public.release_operational_identity_realm(uuid,text) to service_role;

create or replace function public.guard_admin_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_live boolean := false;
  v_new_live boolean := false;
begin
  if tg_op='DELETE' then
    if old.status='active' then
      perform public.release_operational_identity_realm(old.user_id,'admin');
    end if;
    return old;
  end if;

  if tg_op='UPDATE' then
    v_old_live := old.status='active';
  end if;
  v_new_live := new.status='active';

  if v_old_live and (not v_new_live or new.user_id is distinct from old.user_id) then
    perform public.release_operational_identity_realm(old.user_id,'admin');
  end if;
  if v_new_live then
    perform public.claim_operational_identity_realm(new.user_id,'admin');
  end if;
  return new;
end;
$$;

drop trigger if exists admin_users_guard_identity_realm on public.admin_users;
create trigger admin_users_guard_identity_realm
before insert or update of user_id,status or delete on public.admin_users
for each row execute function public.guard_admin_identity_realm();

create or replace function public.guard_partner_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_live boolean := false;
  v_new_live boolean := false;
begin
  if tg_op='DELETE' then
    if old.status='active' and old.removed_at is null then
      perform public.release_operational_identity_realm(old.user_id,'partner');
    end if;
    return old;
  end if;

  if tg_op='UPDATE' then
    v_old_live := old.status='active' and old.removed_at is null;
  end if;
  v_new_live := new.status='active' and new.removed_at is null;

  if v_old_live and (not v_new_live or new.user_id is distinct from old.user_id) then
    perform public.release_operational_identity_realm(old.user_id,'partner');
  end if;
  if v_new_live then
    perform public.claim_operational_identity_realm(new.user_id,'partner');
  end if;
  return new;
end;
$$;

drop trigger if exists partner_users_guard_identity_realm on public.partner_users;
create trigger partner_users_guard_identity_realm
before insert or update of user_id,status,removed_at or delete on public.partner_users
for each row execute function public.guard_partner_identity_realm();

create or replace function public.guard_staff_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_live boolean := false;
  v_new_live boolean := false;
begin
  if tg_op='DELETE' then
    if old.status='active' then
      perform public.release_operational_identity_realm(old.user_id,'staff');
    end if;
    return old;
  end if;

  if tg_op='UPDATE' then
    v_old_live := old.status='active';
  end if;
  v_new_live := new.status='active';

  if v_old_live and (not v_new_live or new.user_id is distinct from old.user_id) then
    perform public.release_operational_identity_realm(old.user_id,'staff');
  end if;
  if v_new_live then
    perform public.claim_operational_identity_realm(new.user_id,'staff');
  end if;
  return new;
end;
$$;

drop trigger if exists staff_users_guard_identity_realm on public.staff_users;
create trigger staff_users_guard_identity_realm
before insert or update of user_id,status or delete on public.staff_users
for each row execute function public.guard_staff_identity_realm();

-- 001 created a full UNIQUE(user_id) on partner_users, which prevents historical
-- removed membership from coexisting with a later membership. Remove only that
-- one-column UNIQUE constraint; retain 018's partial live-membership unique index.
do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid='public.partner_users'::regclass
      and c.contype='u'
      and cardinality(c.conkey)=1
      and exists (
        select 1 from pg_attribute a
        where a.attrelid=c.conrelid
          and a.attnum=c.conkey[1]
          and a.attname='user_id'
      )
  loop
    execute format('alter table public.partner_users drop constraint %I',r.conname);
  end loop;
end;
$$;

create unique index if not exists uq_partner_users_live_user
on public.partner_users(user_id)
where removed_at is null;

comment on table public.operational_identity_realms is
'Canonical live operational-realm registry. One Auth user can be active in exactly one of admin/partner/staff.';
comment on function public.claim_operational_identity_realm(uuid,text) is
'Internal trigger helper. Primary-key conflict serializes concurrent cross-realm activation and rejects a different active realm.';
