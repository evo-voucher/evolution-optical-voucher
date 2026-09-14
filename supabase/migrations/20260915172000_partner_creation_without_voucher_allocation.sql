-- Decouple Partner creation from Voucher allocation.
-- Partner identity/account is created first. Voucher stock is allocated later via Voucher Engine.

CREATE OR REPLACE FUNCTION public.admin_provision_partner_without_allocation(
  p_partner_code text,
  p_partner_name text,
  p_contact_person text,
  p_contact_phone text,
  p_staff_limit integer,
  p_new_user_id uuid,
  p_login_email text,
  p_actor_user_id uuid,
  p_all_branches boolean DEFAULT true,
  p_branch_codes text[] DEFAULT '{}'::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_actor_name text;
  v_partner public.partners%rowtype;
  v_partner_user public.partner_users%rowtype;
  v_requested integer := 0;
  v_resolved integer := 0;
begin
  if not public.is_trusted_service_role() then raise exception 'Trusted server context required'; end if;
  if p_actor_user_id is null or not exists(select 1 from public.admin_users a where a.user_id=p_actor_user_id and a.status='active') then raise exception 'Active Admin actor required'; end if;
  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_actor_name from public.admin_users a where a.user_id=p_actor_user_id and a.status='active';
  if p_new_user_id is null or not exists(select 1 from auth.users u where u.id=p_new_user_id) then raise exception 'Valid Auth user is required'; end if;
  if nullif(trim(coalesce(p_partner_code,'')),'') is null or upper(trim(p_partner_code)) !~ '^[A-Z0-9_-]+$' then raise exception 'Invalid partner code'; end if;
  if nullif(trim(coalesce(p_partner_name,'')),'') is null then raise exception 'Partner name is required'; end if;
  if p_staff_limit is null or p_staff_limit<0 or p_staff_limit>1000 then raise exception 'Staff limit must be 0 to 1000'; end if;
  if nullif(trim(coalesce(p_login_email,'')),'') is null then raise exception 'Login email is required'; end if;

  if not coalesce(p_all_branches,true) then
    v_requested:=coalesce((select count(distinct upper(trim(x))) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null),0);
    if v_requested<1 then raise exception 'Select at least one active claim branch'; end if;
    select count(*) into v_resolved from public.branches b
    where b.status='active' and upper(b.branch_code)=any(select upper(trim(x)) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null);
    if v_resolved<>v_requested then raise exception 'One or more claim branches are invalid or inactive'; end if;
  end if;

  insert into public.partners(partner_code,partner_name,contact_person,contact_phone,voucher_limit,vouchers_issued,staff_limit,staff_access_enabled,status)
  values(upper(trim(p_partner_code)),trim(p_partner_name),nullif(trim(coalesce(p_contact_person,'')),''),nullif(trim(coalesce(p_contact_phone,'')),''),0,0,p_staff_limit,false,'active')
  returning * into v_partner;

  insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
  values(p_new_user_id,v_partner.id,'partner_admin','active',coalesce(nullif(trim(coalesce(p_contact_person,'')),''),trim(p_partner_name)),lower(trim(p_login_email)))
  returning * into v_partner_user;

  insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
  values(v_partner.id,coalesce(p_all_branches,true),p_actor_user_id);

  if not coalesce(p_all_branches,true) then
    insert into public.partner_claim_branches(partner_id,branch_id)
    select v_partner.id,b.id from public.branches b
    where b.status='active' and upper(b.branch_code)=any(select upper(trim(x)) from unnest(coalesce(p_branch_codes,'{}'::text[])) x where nullif(trim(x),'') is not null);
  end if;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata)
  values(
    p_actor_user_id,v_actor_name,'partner_created','partner',v_partner.id::text,v_partner.id,
    jsonb_build_object('partner_code',v_partner.partner_code,'partner_name',v_partner.partner_name,'staff_limit',v_partner.staff_limit,'status',v_partner.status,'all_branches',coalesce(p_all_branches,true),'branch_codes',coalesce(p_branch_codes,'{}'::text[])),
    jsonb_build_object('login_email',lower(trim(p_login_email)),'secret_material_logged',false,'provisioning','partner_only_voucher_engine_allocation','voucher_limit_retired',true)
  );

  return jsonb_build_object(
    'success',true,
    'partner',to_jsonb(v_partner),
    'partner_user_id',v_partner_user.id,
    'user_id',p_new_user_id,
    'claim_all_branches',coalesce(p_all_branches,true),
    'claim_branch_codes',coalesce(p_branch_codes,'{}'::text[])
  );
end;
$function$;

REVOKE ALL ON FUNCTION public.admin_provision_partner_without_allocation(text,text,text,text,integer,uuid,text,uuid,boolean,text[]) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provision_partner_without_allocation(text,text,text,text,integer,uuid,text,uuid,boolean,text[]) TO service_role;
