-- Admin-only revoke for a single issued voucher.
-- Experience branch candidate only. Do not deploy to production without explicit release approval.

create or replace function public.admin_revoke_issued_voucher(
  p_voucher_code text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_id uuid;
  v_partner_id uuid;
  v_status text;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if v_reason is null then
    raise exception 'Revoke reason is required';
  end if;

  if length(v_reason) > 500 then
    raise exception 'Revoke reason is too long';
  end if;

  select v.id, v.partner_id, v.status
    into v_id, v_partner_id, v_status
  from public.vouchers v
  where v.voucher_code = trim(coalesce(p_voucher_code,''))
  for update;

  if not found then
    raise exception 'Voucher not found';
  end if;

  if v_status <> 'active' then
    raise exception 'Only active vouchers can be revoked';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
    into v_admin_name
  from public.admin_users a
  where a.user_id = v_uid and a.status = 'active';

  update public.vouchers
  set status = 'revoked',
      revoked_at = now(),
      revoked_by_user_id = v_uid,
      revoke_reason = v_reason,
      updated_at = now()
  where id = v_id;

  insert into public.admin_audit_log(
    actor_user_id, actor_name, action_type, entity_type, entity_id,
    partner_id, before_data, after_data
  )
  values(
    v_uid, coalesce(v_admin_name,'Admin'), 'voucher_revoked', 'voucher', v_id::text,
    v_partner_id,
    jsonb_build_object('status', v_status),
    jsonb_build_object('status','revoked','voucher_code',trim(coalesce(p_voucher_code,'')),'reason',v_reason)
  );

  return jsonb_build_object(
    'success', true,
    'voucher_id', v_id,
    'voucher_code', trim(coalesce(p_voucher_code,'')),
    'status', 'revoked',
    'reason', v_reason
  );
end;
$function$;

revoke all on function public.admin_revoke_issued_voucher(text,text) from public;
revoke all on function public.admin_revoke_issued_voucher(text,text) from anon;
revoke all on function public.admin_revoke_issued_voucher(text,text) from authenticated;
grant execute on function public.admin_revoke_issued_voucher(text,text) to authenticated;
