-- Compatibility layer for the current Partner portal.
-- Keeps old RPC names while routing all issuance into the new canonical engine.

drop function if exists public.partner_staff_capacity();
create function public.partner_staff_capacity()
returns table(
  partner_id uuid,
  staff_count bigint,
  staff_limit integer,
  staff_access_enabled boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         count(pu2.id) filter (
           where pu2.role='partner_staff'
             and pu2.status in ('active','suspended')
             and pu2.removed_at is null
         ) as staff_count,
         p.staff_limit,
         p.staff_access_enabled
  from public.partners p
  join public.partner_users me
    on me.partner_id=p.id
   and me.user_id=(select auth.uid())
   and me.role='partner_admin'
   and me.status='active'
   and me.removed_at is null
  left join public.partner_users pu2 on pu2.partner_id=p.id
  where p.status='active'
  group by p.id,p.staff_limit,p.staff_access_enabled;
$$;
revoke all on function public.partner_staff_capacity() from public, anon;
grant execute on function public.partner_staff_capacity() to authenticated;

-- Legacy RM60 Partner UI entrypoint.
-- p_customer_ic is accepted only for backward compatibility and is intentionally ignored.
drop function if exists public.create_partner_voucher_controlled(text,text,text,text,date);
create function public.create_partner_voucher_controlled(
  p_customer_name text,
  p_customer_phone text,
  p_customer_ic text,
  p_voucher_type text,
  p_expiry_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version_id uuid;
  v_result jsonb;
begin
  select coalesce(vt.current_version_id,(
    select vv.id
    from public.voucher_versions vv
    where vv.template_id=vt.id and vv.status='active'
    order by vv.version_no desc
    limit 1
  ))
  into v_version_id
  from public.voucher_templates vt
  where vt.template_code='EVO-FREE-GLASSES'
    and vt.status='active'
  limit 1;

  if v_version_id is null then
    raise exception 'Current RM60 voucher engine version is not configured';
  end if;

  v_result:=public.issue_engine_voucher(v_version_id,p_customer_name,p_customer_phone);

  return v_result || jsonb_build_object(
    'compatibility_entrypoint','create_partner_voucher_controlled',
    'legacy_voucher_type',p_voucher_type
  );
end;
$$;
revoke all on function public.create_partner_voucher_controlled(text,text,text,text,date) from public, anon;
grant execute on function public.create_partner_voucher_controlled(text,text,text,text,date) to authenticated;

-- Legacy multi-voucher Partner UI entrypoint.
drop function if exists public.create_partner_multi_voucher_controlled(uuid,text,text);
create function public.create_partner_multi_voucher_controlled(
  p_version_id uuid,
  p_customer_name text,
  p_customer_phone text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.issue_engine_voucher(p_version_id,p_customer_name,p_customer_phone);
$$;
revoke all on function public.create_partner_multi_voucher_controlled(uuid,text,text) from public, anon;
grant execute on function public.create_partner_multi_voucher_controlled(uuid,text,text) to authenticated;

-- TEST001-only cleanup helper retained for development UX.
-- Production vouchers with redemption history can never be deleted here.
drop function if exists public.delete_my_test_voucher(text);
create function public.delete_my_test_voucher(p_voucher_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_partner_id uuid;
  v_voucher public.vouchers%rowtype;
begin
  select p.id into v_partner_id
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=v_uid
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
    and p.partner_code='TEST001'
  limit 1;

  if v_partner_id is null then
    raise exception 'TEST001 Partner Admin only';
  end if;

  select * into v_voucher
  from public.vouchers v
  where v.partner_id=v_partner_id
    and upper(v.voucher_code)=upper(trim(p_voucher_code))
  for update;

  if not found then raise exception 'Test voucher not found'; end if;

  if exists(select 1 from public.redemptions r where r.voucher_id=v_voucher.id) then
    raise exception 'Voucher with redemption history cannot be deleted';
  end if;

  delete from public.voucher_branches where voucher_id=v_voucher.id;
  delete from public.vouchers where id=v_voucher.id;

  update public.partners
  set vouchers_issued=greatest(0,vouchers_issued-1),updated_at=now()
  where id=v_partner_id;

  insert into public.admin_audit_log(actor_user_id,action_type,entity_type,entity_id,partner_id,before_data,metadata)
  values(v_uid,'test_voucher_deleted','voucher',v_voucher.id::text,v_partner_id,
    jsonb_build_object('voucher_code',v_voucher.voucher_code,'voucher_type',v_voucher.voucher_type),
    jsonb_build_object('test_only',true));

  return jsonb_build_object('success',true,'voucher_code',v_voucher.voucher_code);
end;
$$;
revoke all on function public.delete_my_test_voucher(text) from public, anon;
grant execute on function public.delete_my_test_voucher(text) to authenticated;
