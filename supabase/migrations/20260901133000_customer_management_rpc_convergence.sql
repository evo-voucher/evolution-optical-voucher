-- Converge Customer / District management RPCs with current production baseline.
-- Production remains read-only reference. Issuing RPCs are intentionally handled separately.

create or replace function public.admin_add_customer_district(p_district_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_name text:=nullif(trim(coalesce(p_district_name,'')),'');
  v_order integer;
  v_id uuid;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if v_name is null then raise exception 'District name is required'; end if;
  if length(v_name)>80 then raise exception 'District name is too long'; end if;
  select coalesce(max(sort_order),0)+1 into v_order from public.customer_districts;
  insert into public.customer_districts(district_name,sort_order,status,created_by)
  values(v_name,v_order,'active',auth.uid())
  returning id into v_id;
  return jsonb_build_object('success',true,'district_id',v_id,'district_name',v_name,'sort_order',v_order);
exception when unique_violation then
  raise exception 'District already exists';
end;
$function$;

create or replace function public.admin_customer_directory(p_partner_id uuid default null::uuid)
returns table(customer_id uuid, partner_id uuid, partner_code text, partner_name text, customer_name text, customer_phone text, customer_birthday date, customer_district text, first_seen_at timestamp with time zone, last_seen_at timestamp with time zone, voucher_count bigint)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query
  select pc.id,pc.partner_id,p.partner_code,p.partner_name,pc.customer_name,pc.customer_phone,pc.birth_date,pc.district,pc.first_seen_at,pc.last_seen_at,count(v.id)::bigint
  from public.partner_customers pc
  join public.partners p on p.id=pc.partner_id
  left join public.vouchers v on v.customer_id=pc.id
  where p_partner_id is null or pc.partner_id=p_partner_id
  group by pc.id,pc.partner_id,p.partner_code,p.partner_name,pc.customer_name,pc.customer_phone,pc.birth_date,pc.district,pc.first_seen_at,pc.last_seen_at
  order by upper(p.partner_code),upper(pc.customer_name),pc.last_seen_at desc;
end;
$function$;

create or replace function public.admin_customer_district_directory()
returns table(district_id uuid, district_name text, sort_order integer, district_status text)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  return query
  select d.id,d.district_name,d.sort_order,d.status
  from public.customer_districts d
  order by d.sort_order;
end;
$function$;

create or replace function public.admin_move_customer_district(p_district_id uuid, p_direction text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_order integer;
  v_other_id uuid;
  v_other_order integer;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_direction not in ('up','down') then raise exception 'Direction must be up or down'; end if;
  select sort_order into v_order from public.customer_districts where id=p_district_id for update;
  if v_order is null then raise exception 'District not found'; end if;
  if p_direction='up' then
    select id,sort_order into v_other_id,v_other_order from public.customer_districts where sort_order<v_order order by sort_order desc limit 1 for update;
  else
    select id,sort_order into v_other_id,v_other_order from public.customer_districts where sort_order>v_order order by sort_order asc limit 1 for update;
  end if;
  if v_other_id is null then return jsonb_build_object('success',true,'moved',false); end if;
  update public.customer_districts set sort_order=-1000000,updated_at=now() where id=p_district_id;
  update public.customer_districts set sort_order=v_order,updated_at=now() where id=v_other_id;
  update public.customer_districts set sort_order=v_other_order,updated_at=now() where id=p_district_id;
  return jsonb_build_object('success',true,'moved',true);
end;
$function$;

create or replace function public.admin_set_customer_district_status(p_district_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_status not in ('active','inactive') then raise exception 'Invalid district status'; end if;
  update public.customer_districts set status=p_status,updated_at=now() where id=p_district_id;
  if not found then raise exception 'District not found'; end if;
  return jsonb_build_object('success',true,'district_id',p_district_id,'status',p_status);
end;
$function$;

create or replace function public.admin_set_customer_field_requirements(p_phone_required boolean, p_birthday_required boolean, p_district_required boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  update public.system_customer_field_settings
  set phone_required=coalesce(p_phone_required,false),birthday_required=coalesce(p_birthday_required,false),district_required=coalesce(p_district_required,false),updated_at=now(),updated_by=auth.uid()
  where singleton_id=1;
  return jsonb_build_object('success',true,'phone_required',coalesce(p_phone_required,false),'birthday_required',coalesce(p_birthday_required,false),'district_required',coalesce(p_district_required,false));
end;
$function$;

create or replace function public.admin_set_customer_field_requirements(p_phone_required boolean, p_birthday_required boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  insert into public.system_customer_field_settings(singleton_id,phone_required,birthday_required,updated_at,updated_by)
  values(1,coalesce(p_phone_required,false),coalesce(p_birthday_required,false),now(),auth.uid())
  on conflict (singleton_id) do update set phone_required=excluded.phone_required,birthday_required=excluded.birthday_required,updated_at=now(),updated_by=auth.uid();
  return jsonb_build_object('success',true,'phone_required',coalesce(p_phone_required,false),'birthday_required',coalesce(p_birthday_required,false));
end;
$function$;

create or replace function public.customer_district_options()
returns table(district_id uuid, district_name text, sort_order integer)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_realm jsonb;
begin
  v_realm:=public.current_operational_realm();
  if coalesce((v_realm->>'authenticated')::boolean,false) is not true or coalesce(v_realm->>'realm','') not in ('partner','admin') then
    raise exception 'Partner or Admin access required';
  end if;
  return query
  select d.id,d.district_name,d.sort_order
  from public.customer_districts d
  where d.status='active'
  order by d.sort_order;
end;
$function$;

create or replace function public.customer_field_requirements()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_realm jsonb;
  v_phone boolean;
  v_birthday boolean;
  v_district boolean;
begin
  v_realm := public.current_operational_realm();
  if coalesce((v_realm->>'authenticated')::boolean,false) is not true or coalesce(v_realm->>'realm','') not in ('partner','admin') then
    raise exception 'Partner or Admin access required';
  end if;
  select phone_required,birthday_required,district_required into v_phone,v_birthday,v_district
  from public.system_customer_field_settings where singleton_id=1;
  return jsonb_build_object('phone_required',coalesce(v_phone,false),'birthday_required',coalesce(v_birthday,false),'district_required',coalesce(v_district,false));
end;
$function$;

revoke all on function public.admin_add_customer_district(text) from public, anon, authenticated, service_role;
grant execute on function public.admin_add_customer_district(text) to authenticated, service_role;
revoke all on function public.admin_customer_directory(uuid) from public, anon, authenticated, service_role;
grant execute on function public.admin_customer_directory(uuid) to authenticated, service_role;
revoke all on function public.admin_customer_district_directory() from public, anon, authenticated, service_role;
grant execute on function public.admin_customer_district_directory() to authenticated, service_role;
revoke all on function public.admin_move_customer_district(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.admin_move_customer_district(uuid,text) to authenticated, service_role;
revoke all on function public.admin_set_customer_district_status(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.admin_set_customer_district_status(uuid,text) to authenticated, service_role;
revoke all on function public.admin_set_customer_field_requirements(boolean,boolean,boolean) from public, anon, authenticated, service_role;
grant execute on function public.admin_set_customer_field_requirements(boolean,boolean,boolean) to authenticated, service_role;
revoke all on function public.admin_set_customer_field_requirements(boolean,boolean) from public, anon, authenticated, service_role;
grant execute on function public.admin_set_customer_field_requirements(boolean,boolean) to authenticated, service_role;
revoke all on function public.customer_district_options() from public, anon, authenticated, service_role;
grant execute on function public.customer_district_options() to authenticated, service_role;
revoke all on function public.customer_field_requirements() from public, anon, authenticated, service_role;
grant execute on function public.customer_field_requirements() to authenticated, service_role;
