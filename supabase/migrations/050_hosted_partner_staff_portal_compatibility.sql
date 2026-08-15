-- Hosted Partner + Staff portal compatibility layer
-- Purpose: let the current GitHub Partner/Staff portals operate against the
-- existing Evolution Voucher production lineage without rewriting historical
-- Voucher/redemption/Auth records.
--
-- Hosted semantics preserved:
--   vouchers.status: valid | redeemed | expired | revoked
--   redemptions.status: success | reversed
--   redemptions.staff_user_id references staff_users.id in the hosted lineage
--   create_partner_multi_voucher_controlled() remains the proven issuance core

create or replace function public.partner_voucher_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner_id uuid;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select pu.partner_id into v_partner_id
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and lower(coalesce(pu.status,''))='active'
    and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('partner_admin','partner_staff')
    and lower(coalesce(p.status,''))='active'
  limit 1;

  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;

  return jsonb_build_object(
    'partner_id',v_partner_id,
    'issued_total',(select count(*) from public.vouchers v where v.partner_id=v_partner_id),
    'active_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and lower(coalesce(v.status,'')) in ('valid','active')
        and v.expiry_date>=v_today
    ),
    'redeemed_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and lower(coalesce(v.status,''))='redeemed'
    ),
    'expired_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id
        and (
          lower(coalesce(v.status,''))='expired'
          or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<v_today)
        )
    ),
    'revoked_total',(
      select count(*) from public.vouchers v
      where v.partner_id=v_partner_id and lower(coalesce(v.status,''))='revoked'
    ),
    'completed_redemptions',(
      select count(*) from public.redemptions r
      where r.partner_id=v_partner_id and lower(coalesce(r.status,'')) in ('success','completed')
    )
  );
end;
$$;
revoke all on function public.partner_voucher_summary() from public, anon;
grant execute on function public.partner_voucher_summary() to authenticated;

create or replace function public.partner_recent_vouchers(p_limit integer default 50)
returns table(
  voucher_id uuid,
  voucher_code text,
  customer_name text,
  customer_phone text,
  voucher_type text,
  voucher_status text,
  expiry_date date,
  issued_at timestamptz,
  issued_by_name text,
  usage_count integer,
  usage_limit integer,
  last_redeemed_at timestamptz,
  last_branch_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id uuid;
begin
  select pu.partner_id into v_partner_id
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and lower(coalesce(pu.status,''))='active'
    and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('partner_admin','partner_staff')
    and lower(coalesce(p.status,''))='active'
  limit 1;

  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
  if p_limit is null or p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500'; end if;

  return query
  select
    v.id,
    v.voucher_code,
    v.customer_name,
    v.customer_phone,
    v.voucher_type,
    case
      when lower(coalesce(v.status,''))='revoked' then 'revoked'
      when lower(coalesce(v.status,''))='expired'
        or (lower(coalesce(v.status,'')) in ('valid','active') and v.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date)
        then 'expired'
      when lower(coalesce(v.status,''))='redeemed' then 'redeemed'
      else 'active'
    end,
    v.expiry_date,
    v.issued_at,
    v.issued_by_name,
    case when lower(coalesce(v.status,''))='redeemed' then greatest(coalesce(v.usage_count,0),1) else coalesce(v.usage_count,0) end,
    1::integer,
    lr.redeemed_at,
    lr.branch_name
  from public.vouchers v
  left join lateral (
    select r.redeemed_at,b.branch_name
    from public.redemptions r
    left join public.branches b on b.id=r.branch_id
    where r.voucher_id=v.id and lower(coalesce(r.status,'')) in ('success','completed')
    order by r.redeemed_at desc
    limit 1
  ) lr on true
  where v.partner_id=v_partner_id
  order by v.issued_at desc nulls last
  limit p_limit;
end;
$$;
revoke all on function public.partner_recent_vouchers(integer) from public, anon;
grant execute on function public.partner_recent_vouchers(integer) to authenticated;

create or replace function public.partner_issuable_voucher_catalog()
returns table(
  version_id uuid,
  template_id uuid,
  template_code text,
  template_name text,
  version_no integer,
  version_name text,
  voucher_label text,
  face_value numeric,
  discount_percent numeric,
  validity_mode text,
  valid_days integer,
  valid_months integer,
  valid_until date,
  usage_limit integer,
  transferable boolean,
  terms_text text,
  remaining_allocation bigint,
  remaining_supply bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id uuid;
  v_role text;
  v_staff_access_enabled boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select pu.partner_id,lower(coalesce(pu.role,'')),coalesce(p.staff_access_enabled,false)
  into v_partner_id,v_role,v_staff_access_enabled
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and lower(coalesce(pu.status,''))='active'
    and pu.removed_at is null
    and lower(coalesce(pu.role,'')) in ('partner_admin','partner_staff')
    and lower(coalesce(p.status,''))='active'
  limit 1;

  if v_partner_id is null then raise exception 'Active Partner account not found'; end if;
  if v_role='partner_staff' and not v_staff_access_enabled then raise exception 'Staff access is disabled by Partner Admin'; end if;

  return query
  select
    vv.id,
    vt.id,
    vt.template_code,
    vt.template_name,
    vv.version_no,
    vv.version_name,
    case
      when vv.face_value is not null then 'RM'||trim(to_char(vv.face_value,'FM999999990.##'))||' '||vt.template_name
      when vv.discount_percent is not null then trim(to_char(vv.discount_percent,'FM999999990.##'))||'% '||vt.template_name
      else vt.template_name
    end,
    vv.face_value,
    vv.discount_percent,
    coalesce(vv.validity_mode,case lower(coalesce(vv.validity_type,'')) when 'fixed' then 'fixed' else 'days' end),
    vv.valid_days,
    vv.valid_months,
    vv.valid_until,
    coalesce(vv.usage_limit,1),
    coalesce(vv.transferable,true),
    vv.terms_text,
    greatest(0,(a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0))::bigint,
    case when vv.supply_limit is null then null else greatest(0,vv.supply_limit-coalesce(vi.issued_count,0))::bigint end
  from public.voucher_versions vv
  join public.voucher_templates vt on vt.id=vv.template_id and lower(coalesce(vt.status,''))='active'
  join public.partner_voucher_access pva on pva.partner_id=v_partner_id and pva.template_id=vv.template_id
    and lower(coalesce(pva.status,''))='active'
    and (pva.valid_from is null or pva.valid_from<=now())
    and (pva.valid_until is null or pva.valid_until>=now())
  join lateral (
    select pa.id,pa.quantity_allocated,pa.quantity_revoked
    from public.partner_voucher_allocations pa
    where pa.partner_id=v_partner_id
      and pa.version_id=vv.id
      and lower(coalesce(pa.status,''))='active'
      and (pa.valid_from is null or pa.valid_from<=now())
      and (pa.valid_until is null or pa.valid_until>=now())
    order by pa.created_at desc
    limit 1
  ) a on true
  left join lateral (
    select count(*)::bigint as issued_count from public.vouchers v where v.allocation_id=a.id
  ) ai on true
  left join lateral (
    select count(*)::bigint as issued_count from public.vouchers v where v.version_id=vv.id
  ) vi on true
  where lower(coalesce(vv.status,''))='active'
    and (
      coalesce(vv.validity_mode,case lower(coalesce(vv.validity_type,'')) when 'fixed' then 'fixed' else 'days' end)<>'fixed'
      or (vv.valid_until is not null and vv.valid_until>=v_today and (vv.valid_from is null or vv.valid_from<=v_today))
    )
    and (a.quantity_allocated-a.quantity_revoked)-coalesce(ai.issued_count,0)>0
    and (vv.supply_limit is null or vv.supply_limit-coalesce(vi.issued_count,0)>0)
  order by vt.template_name,vv.version_no desc;
end;
$$;
revoke all on function public.partner_issuable_voucher_catalog() from public, anon;
grant execute on function public.partner_issuable_voucher_catalog() to authenticated;

create or replace function public.partner_staff_directory()
returns table(
  staff_id uuid,
  user_id uuid,
  staff_name text,
  login_email text,
  staff_status text,
  created_at timestamptz,
  updated_at timestamptz,
  removed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_partner_id uuid;
begin
  select pu.partner_id into v_partner_id
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and lower(coalesce(pu.role,''))='partner_admin'
    and lower(coalesce(pu.status,''))='active'
    and pu.removed_at is null
    and lower(coalesce(p.status,''))='active'
  limit 1;

  if v_partner_id is null then raise exception 'Active Partner Admin access required'; end if;

  return query
  select pu.id,pu.user_id,pu.staff_name,pu.login_email,pu.status,pu.created_at,pu.updated_at,pu.removed_at
  from public.partner_users pu
  where pu.partner_id=v_partner_id and lower(coalesce(pu.role,''))='partner_staff'
  order by (pu.removed_at is not null),lower(coalesce(pu.staff_name,'')),pu.created_at;
end;
$$;
revoke all on function public.partner_staff_directory() from public, anon;
grant execute on function public.partner_staff_directory() to authenticated;

create or replace function public.issue_engine_voucher(
  p_version_id uuid,
  p_customer_name text,
  p_customer_phone text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.create_partner_multi_voucher_controlled(p_version_id,p_customer_name,p_customer_phone);
$$;
revoke all on function public.issue_engine_voucher(uuid,text,text) from public, anon;
grant execute on function public.issue_engine_voucher(uuid,text,text) to authenticated;

create or replace function public.get_partner_voucher_share(p_voucher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner_id uuid;
  v_code text;
  v_type text;
  v_expiry date;
  v_customer text;
  v_all boolean;
  v_branches jsonb := '[]'::jsonb;
  v_branch_text text := '';
  v_message text;
begin
  select v.partner_id,v.voucher_code,v.voucher_type,v.expiry_date,v.customer_name,v.all_branches
  into v_partner_id,v_code,v_type,v_expiry,v_customer,v_all
  from public.vouchers v
  where v.id=p_voucher_id;
  if not found then raise exception 'Voucher not found'; end if;

  if not public.is_voucher_admin() and not exists(
    select 1
    from public.partner_users pu
    join public.partners p on p.id=pu.partner_id
    where pu.user_id=v_uid and pu.partner_id=v_partner_id
      and lower(coalesce(pu.status,''))='active'
      and pu.removed_at is null
      and lower(coalesce(pu.role,'')) in ('partner_admin','partner_staff')
      and lower(coalesce(p.status,''))='active'
  ) then
    raise exception 'Partner access required';
  end if;

  if v_all then
    select coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
           coalesce(string_agg(b.branch_name||case when nullif(trim(coalesce(b.address,'')),'') is not null then ' — '||b.address else '' end,E'\n' order by b.branch_name),'')
    into v_branches,v_branch_text
    from public.branches b
    where lower(coalesce(b.status,''))='active';
  else
    select coalesce(jsonb_agg(jsonb_build_object('branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb),
           coalesce(string_agg(b.branch_name||case when nullif(trim(coalesce(b.address,'')),'') is not null then ' — '||b.address else '' end,E'\n' order by b.branch_name),'')
    into v_branches,v_branch_text
    from public.voucher_branches vb
    join public.branches b on b.id=vb.branch_id
    where vb.voucher_id=p_voucher_id and lower(coalesce(b.status,''))='active';
  end if;

  v_message := E'Hi 👋\nA little gift for you 🎁✨\nHere is your Evolution Optical Voucher.'
    ||E'\n\nVoucher: '||coalesce(v_type,'Voucher')
    ||E'\nCode: '||coalesce(v_code,'')
    ||case when nullif(trim(coalesce(v_customer,'')),'') is not null then E'\nFor: '||v_customer else '' end
    ||case when v_expiry is not null then E'\nExpiry: '||v_expiry::text else '' end
    ||case when nullif(v_branch_text,'') is not null then E'\n\nRedeem at:\n'||v_branch_text else '' end;

  return jsonb_build_object(
    'success',true,'voucher_id',p_voucher_id,'voucher_code',v_code,'voucher_type',v_type,'expiry_date',v_expiry,
    'branches',v_branches,'message_body',v_message
  );
end;
$$;
revoke all on function public.get_partner_voucher_share(uuid) from public, anon;
grant execute on function public.get_partner_voucher_share(uuid) to authenticated;

create or replace function public.staff_operational_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff public.staff_users%rowtype;
  v_branch public.branches%rowtype;
  v_branches jsonb := '[]'::jsonb;
begin
  select * into v_staff
  from public.staff_users su
  where su.user_id=(select auth.uid()) and lower(coalesce(su.status,''))='active'
  limit 1;
  if not found then raise exception 'Active Staff account not found'; end if;

  if lower(coalesce(v_staff.role,''))='all_branch_manager' then
    select coalesce(jsonb_agg(jsonb_build_object('branch_id',b.id,'branch_code',b.branch_code,'branch_name',b.branch_name,'address',b.address,'phone',b.phone) order by b.branch_name),'[]'::jsonb)
    into v_branches
    from public.branches b
    where lower(coalesce(b.status,''))='active';
  else
    if v_staff.branch_id is null then raise exception 'Staff account has no branch assigned'; end if;
    select * into v_branch from public.branches b where b.id=v_staff.branch_id and lower(coalesce(b.status,''))='active';
    if not found then raise exception 'Assigned branch is not active'; end if;
    v_branches:=jsonb_build_array(jsonb_build_object('branch_id',v_branch.id,'branch_code',v_branch.branch_code,'branch_name',v_branch.branch_name,'address',v_branch.address,'phone',v_branch.phone));
  end if;

  return jsonb_build_object(
    'success',true,'staff_user_id',v_staff.id,'staff_name',v_staff.staff_name,'role',v_staff.role,
    'branch_id',v_staff.branch_id,'branch_selection_required',lower(coalesce(v_staff.role,''))='all_branch_manager','branches',v_branches
  );
end;
$$;
revoke all on function public.staff_operational_context() from public, anon;
grant execute on function public.staff_operational_context() to authenticated;

create or replace function public.staff_today_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff public.staff_users%rowtype;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_count bigint;
begin
  select * into v_staff from public.staff_users su
  where su.user_id=(select auth.uid()) and lower(coalesce(su.status,''))='active' limit 1;
  if not found then raise exception 'Active Staff account not found'; end if;

  select count(*) into v_count
  from public.redemptions r
  where lower(coalesce(r.status,'')) in ('success','completed')
    and (r.redeemed_at at time zone 'Asia/Kuala_Lumpur')::date=v_today
    and (
      lower(coalesce(v_staff.role,''))='all_branch_manager'
      or (lower(coalesce(v_staff.role,''))='manager' and r.branch_id=v_staff.branch_id)
      or (lower(coalesce(v_staff.role,''))='staff' and r.staff_user_id=v_staff.id)
    );

  return jsonb_build_object('success',true,'staff_user_id',v_staff.id,'staff_name',v_staff.staff_name,'role',v_staff.role,'branch_id',v_staff.branch_id,'today_redeemed',v_count);
end;
$$;
revoke all on function public.staff_today_summary() from public, anon;
grant execute on function public.staff_today_summary() to authenticated;

create or replace function public.staff_recent_redemptions(p_limit integer default 20)
returns table(
  redemption_id uuid,
  voucher_id uuid,
  voucher_code text,
  customer_name text,
  voucher_type text,
  partner_name text,
  branch_id uuid,
  branch_name text,
  staff_name text,
  redeem_method text,
  redemption_status text,
  redeemed_at timestamptz,
  notes text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_staff public.staff_users%rowtype;
begin
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'Limit must be between 1 and 100'; end if;
  select * into v_staff from public.staff_users su
  where su.user_id=(select auth.uid()) and lower(coalesce(su.status,''))='active' limit 1;
  if not found then raise exception 'Active Staff account not found'; end if;

  return query
  select r.id,r.voucher_id,v.voucher_code,v.customer_name,v.voucher_type,p.partner_name,r.branch_id,b.branch_name,
         coalesce(r.staff_name_snapshot,su.staff_name),r.redeem_method,
         case when lower(coalesce(r.status,'')) in ('success','completed') then 'completed' else lower(coalesce(r.status,'')) end,
         r.redeemed_at,r.notes
  from public.redemptions r
  join public.vouchers v on v.id=r.voucher_id
  left join public.partners p on p.id=coalesce(r.partner_id,v.partner_id)
  left join public.branches b on b.id=r.branch_id
  left join public.staff_users su on su.id=r.staff_user_id
  where lower(coalesce(v_staff.role,''))='all_branch_manager'
     or (lower(coalesce(v_staff.role,''))='manager' and r.branch_id=v_staff.branch_id)
     or (lower(coalesce(v_staff.role,''))='staff' and r.staff_user_id=v_staff.id)
  order by r.redeemed_at desc nulls last
  limit p_limit;
end;
$$;
revoke all on function public.staff_recent_redemptions(integer) from public, anon;
grant execute on function public.staff_recent_redemptions(integer) to authenticated;

create or replace function public.verify_voucher(
  p_voucher_code text,
  p_branch_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff public.staff_users%rowtype;
  v_voucher public.vouchers%rowtype;
  v_branch_id uuid;
  v_branch_name text;
  v_allowed boolean := false;
  v_expired boolean := false;
  v_redeemed boolean := false;
begin
  select * into v_staff from public.staff_users su
  where su.user_id=(select auth.uid()) and lower(coalesce(su.status,''))='active' limit 1;
  if not found then return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended'); end if;

  if lower(coalesce(v_staff.role,''))='all_branch_manager' then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where upper(b.branch_code)=upper(trim(p_branch_code)) and lower(coalesce(b.status,''))='active' limit 1;
  else
    if v_staff.branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where b.id=v_staff.branch_id and lower(coalesce(b.status,''))='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;

  select * into v_voucher from public.vouchers v where upper(v.voucher_code)=upper(trim(p_voucher_code)) limit 1;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;

  v_expired:=v_voucher.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date;
  select exists(select 1 from public.redemptions r where r.voucher_id=v_voucher.id and lower(coalesce(r.status,'')) in ('success','completed')) into v_redeemed;
  if v_voucher.all_branches then v_allowed:=true;
  else select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  end if;

  return jsonb_build_object(
    'success',true,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,'customer_name',v_voucher.customer_name,
    'customer_phone',v_voucher.customer_phone,'voucher_type',v_voucher.voucher_type,'expiry_date',v_voucher.expiry_date,
    'status',case when v_expired then 'expired' when v_redeemed or lower(coalesce(v_voucher.status,''))='redeemed' then 'redeemed' when lower(coalesce(v_voucher.status,''))='revoked' then 'revoked' else 'valid' end,
    'canonical_status',v_voucher.status,'usage_limit',1,'usage_count',case when v_redeemed or lower(coalesce(v_voucher.status,''))='redeemed' then 1 else 0 end,
    'remaining_uses',case when v_redeemed or lower(coalesce(v_voucher.status,''))='redeemed' then 0 else 1 end,
    'branch_id',v_branch_id,'branch_name',v_branch_name,'branch_allowed',v_allowed,'expired',v_expired,
    'can_redeem',lower(coalesce(v_voucher.status,'')) in ('valid','active') and not v_expired and not v_redeemed and v_allowed
  );
end;
$$;
revoke all on function public.verify_voucher(text,text) from public, anon;
grant execute on function public.verify_voucher(text,text) to authenticated;

create or replace function public.redeem_voucher(
  p_voucher_code text,
  p_notes text default null,
  p_branch_code text default null,
  p_redeem_method text default 'manual_code'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff public.staff_users%rowtype;
  v_voucher public.vouchers%rowtype;
  v_branch_id uuid;
  v_branch_name text;
  v_allowed boolean := false;
  v_now timestamptz := now();
  v_method text := lower(trim(coalesce(p_redeem_method,'manual_code')));
  v_redemption_id uuid;
begin
  if v_method not in ('qr','qr_scan','manual_code','admin') then return jsonb_build_object('success',false,'error','Invalid redeem method'); end if;

  select * into v_staff from public.staff_users su
  where su.user_id=(select auth.uid()) and lower(coalesce(su.status,''))='active' limit 1;
  if not found then return jsonb_build_object('success',false,'error','Staff account is not authorised or is suspended'); end if;

  if lower(coalesce(v_staff.role,''))='all_branch_manager' then
    if nullif(trim(coalesce(p_branch_code,'')),'') is null then return jsonb_build_object('success',false,'error','Branch selection is required for All Branch Manager'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where upper(b.branch_code)=upper(trim(p_branch_code)) and lower(coalesce(b.status,''))='active' limit 1;
  else
    if v_staff.branch_id is null then return jsonb_build_object('success',false,'error','Staff account has no branch assigned'); end if;
    select b.id,b.branch_name into v_branch_id,v_branch_name from public.branches b
    where b.id=v_staff.branch_id and lower(coalesce(b.status,''))='active' limit 1;
  end if;
  if v_branch_id is null then return jsonb_build_object('success',false,'error','Active branch not found'); end if;

  select * into v_voucher from public.vouchers v
  where upper(v.voucher_code)=upper(trim(p_voucher_code)) for update;
  if not found then return jsonb_build_object('success',false,'error','Voucher not found'); end if;
  if lower(coalesce(v_voucher.status,''))='revoked' then return jsonb_build_object('success',false,'error','Voucher has been revoked','status','revoked'); end if;
  if lower(coalesce(v_voucher.status,''))='expired' or v_voucher.expiry_date<(now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('success',false,'error','Voucher has expired','status','expired'); end if;
  if lower(coalesce(v_voucher.status,''))='redeemed' or exists(select 1 from public.redemptions r where r.voucher_id=v_voucher.id and lower(coalesce(r.status,'')) in ('success','completed')) then return jsonb_build_object('success',false,'error','Voucher has already been redeemed','status','redeemed'); end if;
  if lower(coalesce(v_voucher.status,'')) not in ('valid','active') then return jsonb_build_object('success',false,'error','Voucher is not valid','status',v_voucher.status); end if;

  if v_voucher.all_branches then v_allowed:=true;
  else select exists(select 1 from public.voucher_branches vb where vb.voucher_id=v_voucher.id and vb.branch_id=v_branch_id) into v_allowed;
  end if;
  if not v_allowed then return jsonb_build_object('success',false,'error','Voucher cannot be redeemed at this branch'); end if;

  insert into public.redemptions(voucher_id,branch_id,staff_user_id,partner_id,staff_name_snapshot,redeem_method,status,redeemed_at,notes)
  values(v_voucher.id,v_branch_id,v_staff.id,v_voucher.partner_id,v_staff.staff_name,case when v_method='qr' then 'qr_scan' else v_method end,'success',v_now,nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_redemption_id;

  update public.vouchers
  set status='redeemed',redeemed_at=v_now,redeemed_by=v_staff.staff_name,usage_count=greatest(coalesce(usage_count,0),1)
  where id=v_voucher.id;

  return jsonb_build_object(
    'success',true,'redemption_id',v_redemption_id,'voucher_id',v_voucher.id,'voucher_code',v_voucher.voucher_code,
    'customer_name',v_voucher.customer_name,'voucher_type',v_voucher.voucher_type,'branch_id',v_branch_id,'branch_name',v_branch_name,
    'staff_name',v_staff.staff_name,'redeemed_at',v_now,'usage_count',1,'usage_limit',1,'remaining_uses',0,'status','redeemed'
  );
exception when unique_violation then
  return jsonb_build_object('success',false,'error','Voucher has already been redeemed');
end;
$$;
revoke all on function public.redeem_voucher(text,text,text,text) from public, anon;
grant execute on function public.redeem_voucher(text,text,text,text) to authenticated;
