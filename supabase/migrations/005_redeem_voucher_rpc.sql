-- Atomic voucher redemption.
-- This is the transaction boundary for redemption. Never redeem by direct table update.

drop function if exists public.redeem_voucher(text,text,text,text);
create function public.redeem_voucher(
  p_voucher_code text,
  p_notes text default null,
  p_branch_code text default null,
  p_redeem_method text default 'qr'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_staff public.staff_users%rowtype;
  v_voucher public.vouchers%rowtype;
  v_branch_id uuid;
  v_branch_name text;
  v_allowed boolean := false;
  v_new_usage integer;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_redemption_id uuid;
  v_method text;
begin
  if v_uid is null then
    return jsonb_build_object('success',false,'error','Authentication required');
  end if;

  v_method := lower(trim(coalesce(p_redeem_method,'qr')));
  if v_method not in ('qr','manual_code','admin') then
    return jsonb_build_object('success',false,'error','Invalid redeem method');
  end if;

  select * into v_staff
  from public.staff_users su
  where su.user_id = v_uid
    and su.status = 'active'
  limit 1;

  if not found then
    return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended');
  end if;

  if v_staff.role = 'all_branch_manager' then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then
      return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager');
    end if;

    select b.id, b.branch_name
    into v_branch_id, v_branch_name
    from public.branches b
    where upper(b.branch_code) = upper(trim(p_branch_code))
      and b.status = 'active'
    limit 1;
  else
    if v_staff.branch_id is null then
      return jsonb_build_object('success',false,'error','Staff account has no branch assigned');
    end if;

    select b.id, b.branch_name
    into v_branch_id, v_branch_name
    from public.branches b
    where b.id = v_staff.branch_id
      and b.status = 'active'
    limit 1;
  end if;

  if v_branch_id is null then
    return jsonb_build_object('success',false,'error','Active branch not found');
  end if;

  -- Lock the voucher row so concurrent scans serialize here.
  select * into v_voucher
  from public.vouchers v
  where upper(v.voucher_code) = upper(trim(p_voucher_code))
  for update;

  if not found then
    return jsonb_build_object('success',false,'error','Voucher not found');
  end if;

  if v_voucher.status = 'revoked' then
    return jsonb_build_object('success',false,'error','Voucher has been revoked','status',v_voucher.status);
  end if;

  if v_voucher.status = 'expired' or v_voucher.expiry_date < v_today then
    update public.vouchers
    set status = case when status='active' then 'expired' else status end,
        updated_at = v_now
    where id = v_voucher.id;
    return jsonb_build_object('success',false,'error','Voucher has expired','status','expired');
  end if;

  if v_voucher.status = 'redeemed' or v_voucher.usage_count >= v_voucher.usage_limit then
    return jsonb_build_object('success',false,'error','Voucher has already been fully redeemed','status','redeemed');
  end if;

  if v_voucher.status <> 'active' then
    return jsonb_build_object('success',false,'error','Voucher is not active','status',v_voucher.status);
  end if;

  if v_voucher.all_branches then
    v_allowed := true;
  else
    select exists (
      select 1
      from public.voucher_branches vb
      where vb.voucher_id = v_voucher.id
        and vb.branch_id = v_branch_id
    ) into v_allowed;
  end if;

  if not v_allowed then
    return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch');
  end if;

  v_new_usage := v_voucher.usage_count + 1;

  insert into public.redemptions(
    voucher_id,
    partner_id,
    branch_id,
    staff_user_id,
    staff_name_snapshot,
    redeem_method,
    status,
    redeemed_at,
    notes
  ) values (
    v_voucher.id,
    v_voucher.partner_id,
    v_branch_id,
    v_uid,
    v_staff.staff_name,
    v_method,
    'completed',
    v_now,
    nullif(trim(coalesce(p_notes,'')),'')
  ) returning id into v_redemption_id;

  update public.vouchers
  set usage_count = v_new_usage,
      status = case when v_new_usage >= usage_limit then 'redeemed' else 'active' end,
      updated_at = v_now
  where id = v_voucher.id;

  insert into public.admin_audit_log(
    actor_user_id, actor_name, action_type, entity_type, entity_id, partner_id, after_data, metadata
  ) values (
    v_uid,
    v_staff.staff_name,
    'voucher_redeemed',
    'redemption',
    v_redemption_id::text,
    v_voucher.partner_id,
    jsonb_build_object(
      'voucher_id',v_voucher.id,
      'voucher_code',v_voucher.voucher_code,
      'branch_id',v_branch_id,
      'branch_name',v_branch_name,
      'usage_count',v_new_usage,
      'usage_limit',v_voucher.usage_limit
    ),
    jsonb_build_object('redeem_method',v_method)
  );

  return jsonb_build_object(
    'success',true,
    'redemption_id',v_redemption_id,
    'voucher_id',v_voucher.id,
    'voucher_code',v_voucher.voucher_code,
    'customer_name',v_voucher.customer_name,
    'voucher_type',v_voucher.voucher_type,
    'branch_id',v_branch_id,
    'branch_name',v_branch_name,
    'staff_name',v_staff.staff_name,
    'redeemed_at',v_now,
    'usage_count',v_new_usage,
    'usage_limit',v_voucher.usage_limit,
    'remaining_uses',greatest(0,v_voucher.usage_limit-v_new_usage),
    'status',case when v_new_usage >= v_voucher.usage_limit then 'redeemed' else 'active' end
  );
end;
$$;

revoke all on function public.redeem_voucher(text,text,text,text) from public, anon;
grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;
