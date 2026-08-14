-- Identity Realm Exclusivity v1
-- Purpose: prevent one Auth identity from simultaneously operating as Admin,
-- Partner user, and Evolution Staff. Separate operational realms reduce accidental
-- privilege bleed and make authorization easier to reason about.
--
-- Historical/suspended/removed rows may remain for audit. The rule applies only
-- when an identity is being activated for live operational access.

create or replace function public.guard_admin_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'active' then
    if exists (
      select 1 from public.partner_users pu
      where pu.user_id = new.user_id
        and pu.status = 'active'
        and pu.removed_at is null
    ) then
      raise exception 'Auth identity already belongs to an active Partner realm';
    end if;

    if exists (
      select 1 from public.staff_users su
      where su.user_id = new.user_id
        and su.status = 'active'
    ) then
      raise exception 'Auth identity already belongs to an active Staff realm';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists admin_users_guard_identity_realm on public.admin_users;
create trigger admin_users_guard_identity_realm
before insert or update of user_id, status on public.admin_users
for each row execute function public.guard_admin_identity_realm();

create or replace function public.guard_partner_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'active' and new.removed_at is null then
    if exists (
      select 1 from public.admin_users au
      where au.user_id = new.user_id
        and au.status = 'active'
    ) then
      raise exception 'Auth identity already belongs to an active Admin realm';
    end if;

    if exists (
      select 1 from public.staff_users su
      where su.user_id = new.user_id
        and su.status = 'active'
    ) then
      raise exception 'Auth identity already belongs to an active Staff realm';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists partner_users_guard_identity_realm on public.partner_users;
create trigger partner_users_guard_identity_realm
before insert or update of user_id, status, removed_at on public.partner_users
for each row execute function public.guard_partner_identity_realm();

create or replace function public.guard_staff_identity_realm()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'active' then
    if exists (
      select 1 from public.admin_users au
      where au.user_id = new.user_id
        and au.status = 'active'
    ) then
      raise exception 'Auth identity already belongs to an active Admin realm';
    end if;

    if exists (
      select 1 from public.partner_users pu
      where pu.user_id = new.user_id
        and pu.status = 'active'
        and pu.removed_at is null
    ) then
      raise exception 'Auth identity already belongs to an active Partner realm';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists staff_users_guard_identity_realm on public.staff_users;
create trigger staff_users_guard_identity_realm
before insert or update of user_id, status on public.staff_users
for each row execute function public.guard_staff_identity_realm();

-- One canonical operational realm resolver for frontend routing and server checks.
create or replace function public.current_operational_realm()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_partner public.partner_users%rowtype;
  v_staff public.staff_users%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('authenticated',false,'realm',null);
  end if;

  select exists(
    select 1 from public.admin_users au
    where au.user_id=v_uid and au.status='active'
  ) into v_admin;

  if v_admin then
    return jsonb_build_object(
      'authenticated',true,
      'realm','admin',
      'user_id',v_uid
    );
  end if;

  select * into v_partner
  from public.partner_users pu
  where pu.user_id=v_uid
    and pu.status='active'
    and pu.removed_at is null
  limit 1;

  if found then
    return jsonb_build_object(
      'authenticated',true,
      'realm','partner',
      'user_id',v_uid,
      'partner_id',v_partner.partner_id,
      'role',v_partner.role
    );
  end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id=v_uid and su.status='active'
  limit 1;

  if found then
    return jsonb_build_object(
      'authenticated',true,
      'realm','staff',
      'user_id',v_uid,
      'branch_id',v_staff.branch_id,
      'role',v_staff.role
    );
  end if;

  return jsonb_build_object(
    'authenticated',true,
    'realm',null,
    'user_id',v_uid
  );
end;
$$;

revoke all on function public.current_operational_realm() from public, anon;
grant execute on function public.current_operational_realm() to authenticated;
