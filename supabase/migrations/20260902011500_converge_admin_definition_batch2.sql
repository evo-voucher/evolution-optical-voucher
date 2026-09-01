-- Converge remaining Admin RPC definition mismatches on voucher-stage
-- to the current Production behavior.
-- Production remains read-only.

CREATE OR REPLACE FUNCTION public.admin_redemption_report(
  p_partner_id uuid DEFAULT NULL::uuid,
  p_limit integer DEFAULT 500
)
RETURNS TABLE(
  redemption_id uuid,
  voucher_id uuid,
  voucher_code text,
  partner_id uuid,
  partner_name text,
  branch_id uuid,
  branch_name text,
  staff_user_id uuid,
  staff_name text,
  redeem_method text,
  redemption_status text,
  redeemed_at timestamp with time zone,
  notes text,
  reversed_at timestamp with time zone,
  reversed_by_name text,
  reverse_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Limit must be between 1 and 5000';
  end if;

  return query
  select
    r.id,
    r.voucher_id,
    v.voucher_code,
    r.partner_id,
    p.partner_name,
    r.branch_id,
    b.branch_name,
    r.staff_user_id,
    r.staff_name_snapshot,
    r.redeem_method,
    r.status,
    r.redeemed_at,
    r.notes,
    r.reversed_at,
    r.reversed_by_name,
    r.reverse_reason
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  join public.partners p on p.id=r.partner_id
  join public.branches b on b.id=r.branch_id
  where p_partner_id is null or r.partner_id=p_partner_id
  order by r.redeemed_at desc
  limit p_limit;
end;
$function$;

REVOKE ALL ON FUNCTION public.admin_redemption_report(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_redemption_report(uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_partner_staff_limit(
  p_partner_id uuid,
  p_staff_limit integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_limit integer;
  v_active_count integer;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_staff_limit is null or p_staff_limit<0 or p_staff_limit>1000 then raise exception 'Staff limit must be between 0 and 1000'; end if;

  select p.staff_limit into v_old_limit
  from public.partners p where p.id=p_partner_id for update;
  if not found then raise exception 'Partner not found'; end if;

  select count(*) into v_active_count
  from public.partner_users pu
  where pu.partner_id=p_partner_id
    and pu.role='partner_staff'
    and pu.status in ('active','suspended')
    and pu.removed_at is null;

  if p_staff_limit<v_active_count then
    raise exception 'Staff limit cannot be lower than existing non-removed Staff count';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.partners set staff_limit=p_staff_limit,updated_at=now() where id=p_partner_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data)
  values(v_uid,v_admin_name,'partner_staff_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('staff_limit',v_old_limit),jsonb_build_object('staff_limit',p_staff_limit,'existing_staff_count',v_active_count));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'staff_limit',p_staff_limit,'staff_count',v_active_count);
end;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_partner_staff_limit(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_partner_staff_limit(uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_partner_status(
  p_partner_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_status text;
  v_new_status text := lower(trim(coalesce(p_status,'')));
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if v_new_status not in ('active','suspended','archived') then raise exception 'Invalid Partner status'; end if;

  select p.status into v_old_status
  from public.partners p where p.id=p_partner_id for update;
  if not found then raise exception 'Partner not found'; end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a where a.user_id=v_uid and a.status='active';

  update public.partners
  set status=v_new_status,updated_at=now()
  where id=p_partner_id;

  update public.partner_users
  set status=case
      when v_new_status='active' and removed_at is null then 'active'
      when removed_at is not null then 'removed'
      else 'suspended'
    end,
    updated_at=now()
  where partner_id=p_partner_id;

  insert into public.admin_audit_log(actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data)
  values(v_uid,v_admin_name,'partner_status_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('status',v_old_status),jsonb_build_object('status',v_new_status));

  return jsonb_build_object('success',true,'partner_id',p_partner_id,'status',v_new_status);
end;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_partner_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_partner_status(uuid, text) TO authenticated;
