-- Controlled partner voucher issuance.
-- Preserves the proven Partner -> Voucher -> Branch flow without customer IC.
-- Legacy partner.voucher_limit semantics: 0 means no quota, not unlimited.

drop function if exists public.issue_partner_voucher(text,text,text,date);
create function public.issue_partner_voucher(
  p_customer_name text,
  p_customer_phone text,
  p_voucher_type text,
  p_expiry_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner public.partners%rowtype;
  v_partner_user public.partner_users%rowtype;
  v_all_branches boolean := false;
  v_voucher_id uuid;
  v_voucher_code text;
  v_public_token uuid;
  v_branch_count integer := 0;
  v_issue_date date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(coalesce(p_customer_name,'')), '') is null then
    raise exception 'Customer name is required';
  end if;

  if nullif(trim(coalesce(p_voucher_type,'')), '') is null then
    raise exception 'Voucher type is required';
  end if;

  if p_expiry_date is null or p_expiry_date < v_issue_date then
    raise exception 'Expiry date must be today or later';
  end if;

  select pu.* into v_partner_user
  from public.partner_users pu
  where pu.user_id = v_uid
    and pu.status = 'active'
    and pu.removed_at is null
    and pu.role in ('partner_admin','partner_staff')
  limit 1;

  if not found then
    raise exception 'Active Partner account not found';
  end if;

  select * into v_partner
  from public.partners p
  where p.id = v_partner_user.partner_id
  for update;

  if not found or v_partner.status <> 'active' then
    raise exception 'Partner is not active';
  end if;

  if v_partner_user.role = 'partner_staff' and not v_partner.staff_access_enabled then
    raise exception 'Staff access is disabled by Partner Admin';
  end if;

  if v_partner.vouchers_issued >= v_partner.voucher_limit then
    raise exception 'Voucher issuance limit reached';
  end if;

  select coalesce(s.all_branches,false)
  into v_all_branches
  from public.partner_claim_settings s
  where s.partner_id = v_partner.id;

  if not found then
    v_all_branches := false;
  end if;

  if not v_all_branches then
    select count(*) into v_branch_count
    from public.partner_claim_branches pcb
    join public.branches b on b.id = pcb.branch_id
    where pcb.partner_id = v_partner.id
      and b.status = 'active';

    if v_branch_count = 0 then
      raise exception 'No active claim branch is assigned to this Partner';
    end if;
  end if;

  v_voucher_code := 'EO-' || to_char(v_issue_date,'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  insert into public.vouchers(
    voucher_code,
    partner_id,
    customer_name,
    customer_phone,
    voucher_type,
    status,
    expiry_date,
    issued_by_user_id,
    issued_by_name,
    all_branches,
    usage_limit,
    usage_count,
    metadata
  ) values (
    v_voucher_code,
    v_partner.id,
    trim(p_customer_name),
    nullif(trim(coalesce(p_customer_phone,'')),''),
    trim(p_voucher_type),
    'active',
    p_expiry_date,
    v_uid,
    coalesce(nullif(trim(coalesce(v_partner_user.staff_name,'')),''),
      case when v_partner_user.role='partner_admin' then 'Partner Admin' else 'Partner Staff' end),
    v_all_branches,
    1,
    0,
    jsonb_build_object('issuance_path','core_v1','partner_role',v_partner_user.role)
  )
  returning id, public_token into v_voucher_id, v_public_token;

  if not v_all_branches then
    insert into public.voucher_branches(voucher_id, branch_id)
    select v_voucher_id, pcb.branch_id
    from public.partner_claim_branches pcb
    join public.branches b on b.id = pcb.branch_id
    where pcb.partner_id = v_partner.id
      and b.status = 'active';
  end if;

  update public.partners
  set vouchers_issued = vouchers_issued + 1,
      updated_at = now()
  where id = v_partner.id;

  insert into public.admin_audit_log(
    actor_user_id, actor_name, action_type, entity_type, entity_id, partner_id, after_data, metadata
  ) values (
    v_uid,
    coalesce(nullif(trim(coalesce(v_partner_user.staff_name,'')),''), v_partner_user.role),
    'voucher_issued',
    'voucher',
    v_voucher_id::text,
    v_partner.id,
    jsonb_build_object('voucher_code',v_voucher_code,'voucher_type',trim(p_voucher_type),'expiry_date',p_expiry_date),
    jsonb_build_object('all_branches',v_all_branches)
  );

  return jsonb_build_object(
    'success',true,
    'voucher_id',v_voucher_id,
    'voucher_code',v_voucher_code,
    'public_token',v_public_token,
    'partner_id',v_partner.id,
    'voucher_type',trim(p_voucher_type),
    'expiry_date',p_expiry_date,
    'all_branches',v_all_branches,
    'remaining',greatest(0,v_partner.voucher_limit-v_partner.vouchers_issued-1)
  );
end;
$$;

revoke all on function public.issue_partner_voucher(text,text,text,date) from public, anon;
grant execute on function public.issue_partner_voucher(text,text,text,date) to authenticated;
