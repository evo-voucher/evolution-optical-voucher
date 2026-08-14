-- Partner Admin password-reset audit boundary v1.
-- Auth password mutation remains in trusted Edge code; this RPC owns the
-- database audit row under the original authenticated Admin caller context.

create or replace function public.admin_record_partner_password_reset(
  p_partner_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_partner public.partners%rowtype;
  v_partner_admin public.partner_users%rowtype;
begin
  if v_uid is null or not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a
  where a.user_id=v_uid and a.status='active';

  select * into v_partner from public.partners p where p.id=p_partner_id;
  if not found then raise exception 'Partner not found'; end if;

  select * into v_partner_admin
  from public.partner_users pu
  where pu.partner_id=v_partner.id
    and pu.role='partner_admin'
    and pu.removed_at is null
  limit 1;
  if not found then raise exception 'Partner Admin account not found'; end if;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,after_data,metadata
  ) values (
    v_uid,v_admin_name,'partner_password_reset','partner_user',v_partner_admin.id::text,v_partner.id,
    jsonb_build_object('partner_code',v_partner.partner_code,'login_email',v_partner_admin.login_email),
    jsonb_build_object('secret_material_logged',false,'sessions_signed_out',true)
  );

  return jsonb_build_object(
    'success',true,
    'partner_id',v_partner.id,
    'partner_name',v_partner.partner_name,
    'partner_user_id',v_partner_admin.id,
    'user_id',v_partner_admin.user_id
  );
end;
$$;

revoke all on function public.admin_record_partner_password_reset(uuid) from public, anon;
grant execute on function public.admin_record_partner_password_reset(uuid) to authenticated;

comment on function public.admin_record_partner_password_reset(uuid) is
'Authenticated Admin-only audit boundary called after trusted Edge code successfully resets the Partner Admin Auth password.';
