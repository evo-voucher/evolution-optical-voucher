-- Secure first-Admin bootstrap boundary for hosted legacy production.
-- Public signup is never sufficient by itself: bootstrap additionally requires a
-- one-time high-entropy setup code stored only as a SHA-256 digest in the DB.
-- Once an active Admin exists, bootstrap is unavailable regardless of the code.

create table if not exists public.admin_bootstrap_config (
  singleton boolean primary key default true check (singleton),
  setup_code_hash text,
  enabled boolean not null default false,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.admin_bootstrap_config(singleton, enabled)
values(true, false)
on conflict(singleton) do nothing;

alter table public.admin_bootstrap_config enable row level security;
revoke all on table public.admin_bootstrap_config from public, anon, authenticated;

create or replace function public.admin_bootstrap_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_has_admin boolean;
  v_enabled boolean := false;
begin
  select exists(
    select 1
    from public.partner_users pu
    where lower(coalesce(pu.role,''))='admin'
      and lower(coalesce(pu.status,''))='active'
      and pu.removed_at is null
  ) into v_has_admin;

  select coalesce(c.enabled,false)
  into v_enabled
  from public.admin_bootstrap_config c
  where c.singleton=true;

  return jsonb_build_object(
    'bootstrap_available', (not v_has_admin) and v_enabled,
    'admin_exists', v_has_admin
  );
end;
$$;
revoke all on function public.admin_bootstrap_status() from public;
grant execute on function public.admin_bootstrap_status() to anon, authenticated, service_role;

create or replace function public.service_set_admin_bootstrap_code(p_setup_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if nullif(trim(coalesce(p_setup_code,'')),'') is null or length(p_setup_code) < 24 then
    raise exception 'Setup code must be at least 24 characters';
  end if;

  if exists(
    select 1 from public.partner_users pu
    where lower(coalesce(pu.role,''))='admin'
      and lower(coalesce(pu.status,''))='active'
      and pu.removed_at is null
  ) then
    raise exception 'An active Admin already exists';
  end if;

  insert into public.admin_bootstrap_config(singleton,setup_code_hash,enabled,consumed_at,updated_at)
  values(true,encode(digest(p_setup_code,'sha256'),'hex'),true,null,now())
  on conflict(singleton) do update
  set setup_code_hash=excluded.setup_code_hash,
      enabled=true,
      consumed_at=null,
      updated_at=now();

  return jsonb_build_object('success',true,'bootstrap_available',true);
end;
$$;
revoke all on function public.service_set_admin_bootstrap_code(text) from public, anon, authenticated;
grant execute on function public.service_set_admin_bootstrap_code(text) to service_role;

create or replace function public.service_bootstrap_first_admin(
  p_user_id uuid,
  p_login_email text,
  p_setup_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_partner_id uuid;
  v_cfg public.admin_bootstrap_config%rowtype;
begin
  if p_user_id is null then raise exception 'Auth user_id is required'; end if;
  if nullif(trim(coalesce(p_login_email,'')),'') is null then raise exception 'Login email is required'; end if;
  if nullif(coalesce(p_setup_code,''),'') is null then raise exception 'Setup code is required'; end if;

  -- Serialize all first-Admin claims. Two simultaneous callers cannot both win.
  perform pg_advisory_xact_lock(hashtextextended('evolution_voucher:first_admin_bootstrap',0));

  if exists(
    select 1 from public.partner_users pu
    where lower(coalesce(pu.role,''))='admin'
      and lower(coalesce(pu.status,''))='active'
      and pu.removed_at is null
  ) then
    raise exception 'First Admin setup is already complete';
  end if;

  select * into v_cfg
  from public.admin_bootstrap_config c
  where c.singleton=true
  for update;

  if not found or not coalesce(v_cfg.enabled,false) or v_cfg.setup_code_hash is null then
    raise exception 'First Admin setup is not enabled';
  end if;

  if encode(digest(p_setup_code,'sha256'),'hex') <> v_cfg.setup_code_hash then
    raise exception 'Invalid setup code';
  end if;

  select p.id into v_admin_partner_id
  from public.partners p
  where upper(coalesce(p.partner_code,''))='ADMIN'
  order by p.created_at nulls last
  limit 1
  for update;

  if v_admin_partner_id is null then
    insert into public.partners(
      partner_code,partner_name,voucher_limit,vouchers_issued,status,staff_limit,staff_access_enabled
    ) values (
      'ADMIN','Evolution Optical Admin',0,0,'active',0,false
    ) returning id into v_admin_partner_id;
  else
    update public.partners
    set status='active'
    where id=v_admin_partner_id;
  end if;

  insert into public.partner_users(
    user_id,partner_id,role,status,login_email,staff_name,removed_at
  ) values (
    p_user_id,v_admin_partner_id,'admin','active',lower(trim(p_login_email)),'Evolution Optical Admin',null
  );

  update public.admin_bootstrap_config
  set enabled=false,
      consumed_at=now(),
      updated_at=now()
  where singleton=true;

  return jsonb_build_object(
    'success',true,
    'user_id',p_user_id,
    'realm','admin',
    'partner_id',v_admin_partner_id
  );
end;
$$;
revoke all on function public.service_bootstrap_first_admin(uuid,text,text) from public, anon, authenticated;
grant execute on function public.service_bootstrap_first_admin(uuid,text,text) to service_role;

comment on table public.admin_bootstrap_config is
'One-time first-Admin setup gate. Stores only a SHA-256 setup-code digest and auto-disables after successful bootstrap.';
comment on function public.admin_bootstrap_status() is
'Public boolean bootstrap readiness only; exposes no setup secret or Admin identity.';
comment on function public.service_bootstrap_first_admin(uuid,text,text) is
'Service-role-only atomic first Admin claim guarded by one-time setup code and transaction advisory lock.';
