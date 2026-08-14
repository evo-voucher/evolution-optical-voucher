-- Voucher verification for Evolution Optical staff.
-- Read-only verification. No voucher state is mutated here.

drop function if exists public.verify_voucher(text,text);
create function public.verify_voucher(
  p_voucher_code text,
  p_branch_code text default null
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
  v_expired boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('success',false,'error','Authentication required');
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

  select * into v_voucher
  from public.vouchers v
  where upper(v.voucher_code) = upper(trim(p_voucher_code))
  limit 1;

  if not found then
    return jsonb_build_object('success',false,'error','Voucher not found');
  end if;

  v_expired := v_voucher.expiry_date < (now() at time zone 'Asia/Kuala_Lumpur')::date;

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

  return jsonb_build_object(
    'success',true,
    'voucher_id',v_voucher.id,
    'voucher_code',v_voucher.voucher_code,
    'customer_name',v_voucher.customer_name,
    'customer_phone',v_voucher.customer_phone,
    'voucher_type',v_voucher.voucher_type,
    'expiry_date',v_voucher.expiry_date,
    'status',v_voucher.status,
    'usage_limit',v_voucher.usage_limit,
    'usage_count',v_voucher.usage_count,
    'remaining_uses',greatest(0,v_voucher.usage_limit-v_voucher.usage_count),
    'branch_id',v_branch_id,
    'branch_name',v_branch_name,
    'branch_allowed',v_allowed,
    'expired',v_expired,
    'can_redeem',
      v_voucher.status = 'active'
      and not v_expired
      and v_allowed
      and v_voucher.usage_count < v_voucher.usage_limit
  );
end;
$$;

revoke all on function public.verify_voucher(text,text) from public, anon;
grant execute on function public.verify_voucher(text,text) to authenticated;
