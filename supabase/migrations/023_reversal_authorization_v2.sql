-- Reversal authorization v2
-- Replace the brittle time-window heuristic with an explicit transaction-local
-- authorization marker set only by the controlled reversal RPC.

create or replace function public.guard_voucher_immutable_identity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_reversal_allowed boolean := coalesce(current_setting('evo.reversal_allowed', true),'off') = 'on';
  v_reversal_voucher_id text := current_setting('evo.reversal_voucher_id', true);
begin
  if new.id is distinct from old.id
     or new.voucher_code is distinct from old.voucher_code
     or new.public_token is distinct from old.public_token
     or new.partner_id is distinct from old.partner_id
     or new.issued_at is distinct from old.issued_at
     or new.issued_by_user_id is distinct from old.issued_by_user_id
     or new.template_id is distinct from old.template_id
     or new.version_id is distinct from old.version_id
     or new.allocation_id is distinct from old.allocation_id
     or new.usage_limit is distinct from old.usage_limit then
    raise exception 'Immutable voucher identity fields cannot be changed after issuance';
  end if;

  if new.usage_count < old.usage_count then
    if not v_reversal_allowed or v_reversal_voucher_id is distinct from old.id::text then
      raise exception 'Voucher usage_count cannot decrease outside a controlled reversal';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.reverse_redemption(
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
  v_new_status text;
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

  if not found then raise exception 'Redemption not found'; end if;
  if v_redemption.status='reversed' then
    return jsonb_build_object('success',false,'error','Redemption is already reversed');
  end if;

  select * into v_voucher
  from public.vouchers v
  where v.id=v_redemption.voucher_id
  for update;
  if not found then raise exception 'Voucher not found'; end if;

  update public.redemptions
  set status='reversed',
      reversed_at=now(),
      reversed_by_user_id=v_uid,
      reversed_by_name=v_admin_name,
      reverse_reason=trim(p_reason)
  where id=v_redemption.id;

  v_new_usage := greatest(0,v_voucher.usage_count-1);
  v_new_status := case
    when v_voucher.status='revoked' then 'revoked'
    when v_voucher.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
    when v_new_usage < v_voucher.usage_limit then 'active'
    else 'redeemed'
  end;

  perform set_config('evo.reversal_allowed','on',true);
  perform set_config('evo.reversal_voucher_id',v_voucher.id::text,true);

  update public.vouchers
  set usage_count=v_new_usage,
      status=v_new_status,
      updated_at=now()
  where id=v_voucher.id;

  perform set_config('evo.reversal_allowed','off',true);
  perform set_config('evo.reversal_voucher_id','',true);

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,v_admin_name,'redemption_reversed','redemption',v_redemption.id::text,v_redemption.partner_id,
    jsonb_build_object('status',v_redemption.status,'voucher_usage_count',v_voucher.usage_count),
    jsonb_build_object('status','reversed','voucher_usage_count',v_new_usage,'voucher_status',v_new_status),
    jsonb_build_object('reason',trim(p_reason),'authorization','transaction_scoped')
  );

  return jsonb_build_object(
    'success',true,
    'redemption_id',v_redemption.id,
    'voucher_id',v_voucher.id,
    'voucher_code',v_voucher.voucher_code,
    'usage_count',v_new_usage,
    'status',v_new_status
  );
end;
$$;

revoke all on function public.reverse_redemption(uuid,text) from public, anon;
grant execute on function public.reverse_redemption(uuid,text) to authenticated;
