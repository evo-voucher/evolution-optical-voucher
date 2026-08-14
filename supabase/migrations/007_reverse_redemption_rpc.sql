-- Controlled redemption reversal.
-- Reversal never deletes history. It marks the redemption reversed and restores voucher usage atomically.

drop function if exists public.reverse_redemption(uuid,text);
create function public.reverse_redemption(
  p_redemption_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_redemption public.redemptions%rowtype;
  v_voucher public.vouchers%rowtype;
  v_new_usage integer;
begin
  if v_uid is null or not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Reverse reason is required';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin')
  into v_admin_name
  from public.admin_users a
  where a.user_id=v_uid and a.status='active';

  select * into v_redemption
  from public.redemptions r
  where r.id=p_redemption_id
  for update;

  if not found then
    raise exception 'Redemption not found';
  end if;

  if v_redemption.status='reversed' then
    return jsonb_build_object('success',false,'error','Redemption is already reversed');
  end if;

  select * into v_voucher
  from public.vouchers v
  where v.id=v_redemption.voucher_id
  for update;

  if not found then
    raise exception 'Voucher not found';
  end if;

  update public.redemptions
  set status='reversed',
      reversed_at=now(),
      reversed_by_user_id=v_uid,
      reversed_by_name=v_admin_name,
      reverse_reason=trim(p_reason)
  where id=v_redemption.id;

  v_new_usage := greatest(0,v_voucher.usage_count-1);

  update public.vouchers
  set usage_count=v_new_usage,
      status=case
        when status='revoked' then 'revoked'
        when expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
        when v_new_usage < usage_limit then 'active'
        else 'redeemed'
      end,
      updated_at=now()
  where id=v_voucher.id;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,v_admin_name,'redemption_reversed','redemption',v_redemption.id::text,v_redemption.partner_id,
    jsonb_build_object('status',v_redemption.status,'voucher_usage_count',v_voucher.usage_count),
    jsonb_build_object('status','reversed','voucher_usage_count',v_new_usage),
    jsonb_build_object('reason',trim(p_reason))
  );

  return jsonb_build_object(
    'success',true,
    'redemption_id',v_redemption.id,
    'voucher_id',v_voucher.id,
    'voucher_code',v_voucher.voucher_code,
    'usage_count',v_new_usage,
    'status',case
      when v_voucher.status='revoked' then 'revoked'
      when v_voucher.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
      when v_new_usage < v_voucher.usage_limit then 'active'
      else 'redeemed'
    end
  );
end;
$$;

revoke all on function public.reverse_redemption(uuid,text) from public, anon;
grant execute on function public.reverse_redemption(uuid,text) to authenticated;
