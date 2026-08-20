-- Admin-only update for Partner global voucher limit.
-- 0 means unlimited. Experience branch candidate only.

create or replace function public.admin_set_partner_voucher_limit(
  p_partner_id uuid,
  p_voucher_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_limit integer;
  v_issued bigint;
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if p_voucher_limit is null or p_voucher_limit < 0 then
    raise exception 'Voucher limit must be zero or greater';
  end if;

  select p.voucher_limit
    into v_old_limit
  from public.partners p
  where p.id = p_partner_id
  for update;

  if not found then
    raise exception 'Partner not found';
  end if;

  select count(*)
    into v_issued
  from public.vouchers v
  where v.partner_id = p_partner_id;

  if p_voucher_limit <> 0 and p_voucher_limit < v_issued then
    raise exception 'Voucher limit cannot be lower than vouchers already issued';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
    into v_admin_name
  from public.admin_users a
  where a.user_id = v_uid and a.status = 'active';

  update public.partners
  set voucher_limit = p_voucher_limit,
      updated_at = now()
  where id = p_partner_id;

  insert into public.admin_audit_log(
    actor_user_id, actor_name, action_type, entity_type, entity_id,
    partner_id, before_data, after_data
  )
  values(
    v_uid, coalesce(v_admin_name,'Admin'), 'partner_voucher_limit_changed',
    'partner', p_partner_id::text, p_partner_id,
    jsonb_build_object('voucher_limit', v_old_limit),
    jsonb_build_object('voucher_limit', p_voucher_limit, 'vouchers_issued', v_issued)
  );

  return jsonb_build_object(
    'success', true,
    'partner_id', p_partner_id,
    'voucher_limit', p_voucher_limit,
    'voucher_limit_unlimited', p_voucher_limit = 0,
    'vouchers_issued', v_issued
  );
end;
$function$;

revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from public;
revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from anon;
revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from authenticated;
grant execute on function public.admin_set_partner_voucher_limit(uuid,integer) to authenticated;
