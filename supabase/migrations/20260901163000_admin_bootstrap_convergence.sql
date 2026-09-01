-- Converge canonical Admin bootstrap functions with Production.
-- Production was read-only; definitions and explicit ACLs were copied verbatim.

create or replace function public.admin_bootstrap_status()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_has_admin boolean;
  v_enabled boolean := false;
begin
  select exists(
    select 1 from public.admin_users au
    where au.status = 'active'
  ) into v_has_admin;

  select coalesce(c.enabled,false)
  into v_enabled
  from public.admin_bootstrap_config c
  where c.singleton = true;

  return jsonb_build_object(
    'bootstrap_available', (not v_has_admin) and v_enabled,
    'admin_exists', v_has_admin
  );
end;
$function$;

create or replace function public.service_bootstrap_first_admin(
  p_user_id uuid,
  p_display_name text,
  p_setup_code text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_cfg public.admin_bootstrap_config%rowtype;
begin
  if p_user_id is null then raise exception 'Auth user_id is required'; end if;
  if nullif(coalesce(p_setup_code,''),'') is null then raise exception 'Setup code is required'; end if;

  perform pg_advisory_xact_lock(hashtextextended('evolution_voucher:canonical_first_admin',0));

  if exists(select 1 from public.admin_users au where au.status='active') then
    raise exception 'First Admin setup is already complete';
  end if;

  select * into v_cfg
  from public.admin_bootstrap_config c
  where c.singleton=true
  for update;

  if not found or not coalesce(v_cfg.enabled,false) or v_cfg.setup_code_hash is null then
    raise exception 'First Admin setup is not enabled';
  end if;

  if encode(extensions.digest(p_setup_code,'sha256'),'hex') <> v_cfg.setup_code_hash then
    raise exception 'Invalid setup code';
  end if;

  insert into public.admin_users(user_id, display_name, status)
  values(p_user_id, nullif(trim(coalesce(p_display_name,'')),''), 'active');

  update public.admin_bootstrap_config
  set enabled=false,
      consumed_at=now(),
      updated_at=now()
  where singleton=true;

  return jsonb_build_object('success',true,'user_id',p_user_id,'realm','admin');
end;
$function$;

create or replace function public.service_validate_admin_bootstrap_code(p_setup_code text)
returns boolean
language plpgsql
stable security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_hash text;
  v_enabled boolean;
begin
  if exists(select 1 from public.admin_users au where au.status='active') then
    return false;
  end if;

  select c.setup_code_hash, c.enabled
  into v_hash, v_enabled
  from public.admin_bootstrap_config c
  where c.singleton=true;

  if not coalesce(v_enabled,false) or v_hash is null or nullif(coalesce(p_setup_code,''),'') is null then
    return false;
  end if;

  return encode(extensions.digest(p_setup_code,'sha256'),'hex') = v_hash;
end;
$function$;

revoke all on function public.admin_bootstrap_status() from public, anon, authenticated;
grant execute on function public.admin_bootstrap_status() to service_role;

revoke all on function public.service_bootstrap_first_admin(uuid,text,text) from public, anon, authenticated;
grant execute on function public.service_bootstrap_first_admin(uuid,text,text) to service_role;

revoke all on function public.service_validate_admin_bootstrap_code(text) from public, anon, authenticated;
grant execute on function public.service_validate_admin_bootstrap_code(text) to service_role;
