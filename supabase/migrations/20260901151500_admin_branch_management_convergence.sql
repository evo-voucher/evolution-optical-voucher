-- Converge Admin branch directory and management RPCs with Production.
-- Production remains read-only reference.

create or replace function public.admin_active_branches()
returns table(branch_id uuid, branch_code text, branch_name text, address text, phone text)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query select b.id,b.branch_code,b.branch_name,b.address,b.phone from public.branches b where b.status='active' order by b.branch_name,b.branch_code;
end;
$function$;

create or replace function public.admin_branch_directory()
returns table(branch_id uuid, branch_code text, branch_name text, address text, phone text, branch_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select b.id,b.branch_code,b.branch_name,b.address,b.phone,b.status,b.created_at,b.updated_at
  from public.branches b
  order by case b.status when 'active' then 0 when 'inactive' then 1 else 2 end,
           b.branch_name,
           b.branch_code;
end;
$function$;

create or replace function public.admin_update_branch(
  p_branch_id uuid,
  p_branch_name text,
  p_address text default null::text,
  p_phone text default null::text,
  p_status text default 'active'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_admin_name text;
  v_old public.branches%rowtype;
  v_new public.branches%rowtype;
  v_status text := lower(trim(coalesce(p_status,'')));
  v_name text := trim(coalesce(p_branch_name,''));
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;
  if p_branch_id is null then raise exception 'Branch is required'; end if;
  if v_name='' then raise exception 'Branch name is required'; end if;
  if v_status not in ('active','inactive','closed') then raise exception 'Invalid Branch status'; end if;

  select * into v_old from public.branches where id=p_branch_id for update;
  if not found then raise exception 'Branch not found'; end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.branches
  set branch_name=v_name,
      address=nullif(trim(coalesce(p_address,'')),''),
      phone=nullif(trim(coalesce(p_phone,'')),''),
      status=v_status,
      updated_at=now()
  where id=p_branch_id
  returning * into v_new;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,before_data,after_data,metadata
  ) values(
    v_uid,v_admin_name,'branch_updated','branch',p_branch_id::text,
    jsonb_build_object('branch_code',v_old.branch_code,'branch_name',v_old.branch_name,'address',v_old.address,'phone',v_old.phone,'status',v_old.status),
    jsonb_build_object('branch_code',v_new.branch_code,'branch_name',v_new.branch_name,'address',v_new.address,'phone',v_new.phone,'status',v_new.status),
    jsonb_build_object('branch_code_immutable',true,'delete_supported',false)
  );

  return jsonb_build_object(
    'success',true,
    'branch',jsonb_build_object(
      'branch_id',v_new.id,
      'branch_code',v_new.branch_code,
      'branch_name',v_new.branch_name,
      'address',v_new.address,
      'phone',v_new.phone,
      'status',v_new.status
    )
  );
end;
$function$;

revoke all on function public.admin_active_branches() from public, anon, authenticated, service_role;
grant execute on function public.admin_active_branches() to authenticated;

revoke all on function public.admin_branch_directory() from public, anon, authenticated, service_role;
grant execute on function public.admin_branch_directory() to authenticated;

revoke all on function public.admin_update_branch(uuid,text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.admin_update_branch(uuid,text,text,text,text) to authenticated;
