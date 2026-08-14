-- Canonical Partner voucher quota semantics v1
-- Business rule: partners.voucher_limit = 0 means unlimited.
-- Enforce the Partner-wide limit at the Voucher INSERT boundary so every
-- issuance path (Engine, compatibility RPCs, future trusted code) shares one
-- authoritative rule based on count(public.vouchers), not cached counters.

create or replace function public.guard_partner_global_voucher_quota()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_limit integer;
  v_issued bigint;
begin
  if new.partner_id is null then
    raise exception 'Voucher partner_id is required';
  end if;

  -- Serialize Partner-wide issuance decisions on the Partner row.
  select p.voucher_limit
  into v_limit
  from public.partners p
  where p.id=new.partner_id
    and p.status='active'
  for update;

  if not found then
    raise exception 'Active Partner not found';
  end if;

  -- Zero is the explicit unlimited sentinel.
  if v_limit=0 then
    return new;
  end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.partner_id=new.partner_id;

  if v_issued >= v_limit then
    raise exception 'Partner voucher limit reached';
  end if;

  return new;
end;
$$;

drop trigger if exists vouchers_guard_global_partner_quota on public.vouchers;
create trigger vouchers_guard_global_partner_quota
before insert on public.vouchers
for each row execute function public.guard_partner_global_voucher_quota();

comment on function public.guard_partner_global_voucher_quota() is
'Canonical Partner-wide issuance guard. voucher_limit=0 means unlimited; positive limits are enforced from count(vouchers) at INSERT time.';

-- Override 025: zero remains valid even after vouchers have already been issued,
-- because zero means unlimited rather than zero-capacity.
create or replace function public.admin_set_partner_voucher_limit(
  p_partner_id uuid,
  p_voucher_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin_name text;
  v_old_limit integer;
  v_issued bigint;
begin
  if not public.is_voucher_admin() then raise exception 'Admin access required'; end if;
  if p_voucher_limit is null or p_voucher_limit<0 then raise exception 'Voucher limit must be zero or greater'; end if;

  select p.voucher_limit into v_old_limit
  from public.partners p
  where p.id=p_partner_id
  for update;
  if not found then raise exception 'Partner not found'; end if;

  select count(*) into v_issued
  from public.vouchers v
  where v.partner_id=p_partner_id;

  if p_voucher_limit<>0 and p_voucher_limit<v_issued then
    raise exception 'Voucher limit cannot be lower than vouchers already issued';
  end if;

  select coalesce(nullif(trim(a.display_name),''),'Admin') into v_admin_name
  from public.admin_users a
  where a.user_id=v_uid and a.status='active';

  update public.partners
  set voucher_limit=p_voucher_limit,updated_at=now()
  where id=p_partner_id;

  insert into public.admin_audit_log(
    actor_user_id,actor_name,action_type,entity_type,entity_id,partner_id,before_data,after_data,metadata
  ) values (
    v_uid,v_admin_name,'partner_voucher_limit_changed','partner',p_partner_id::text,p_partner_id,
    jsonb_build_object('voucher_limit',v_old_limit),
    jsonb_build_object('voucher_limit',p_voucher_limit,'vouchers_issued',v_issued,'unlimited',p_voucher_limit=0),
    jsonb_build_object('issuance_source_of_truth','vouchers','zero_means_unlimited',true)
  );

  return jsonb_build_object(
    'success',true,
    'partner_id',p_partner_id,
    'voucher_limit',p_voucher_limit,
    'vouchers_issued',v_issued,
    'unlimited',p_voucher_limit=0,
    'issuance_source_of_truth','vouchers'
  );
end;
$$;

revoke all on function public.admin_set_partner_voucher_limit(uuid,integer) from public, anon;
grant execute on function public.admin_set_partner_voucher_limit(uuid,integer) to authenticated;

-- Override 024 dashboard semantics so unlimited is represented explicitly and
-- never displayed as "0 remaining".
create or replace function public.get_my_partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'partner_id',p.id,
    'partner_code',p.partner_code,
    'partner_name',p.partner_name,
    'voucher_limit',p.voucher_limit,
    'voucher_limit_unlimited',p.voucher_limit=0,
    'vouchers_issued',(select count(*) from public.vouchers v where v.partner_id=p.id),
    'remaining',case
      when p.voucher_limit=0 then null
      else greatest(0,p.voucher_limit-(select count(*) from public.vouchers v where v.partner_id=p.id))
    end,
    'partner_status',p.status,
    'role',pu.role,
    'staff_name',pu.staff_name,
    'staff_access_enabled',p.staff_access_enabled,
    'staff_limit',p.staff_limit,
    'can_issue_voucher',case
      when pu.role='partner_admin' then true
      when pu.role='partner_staff' then p.staff_access_enabled
      else false
    end
  ) into v_result
  from public.partner_users pu
  join public.partners p on p.id=pu.partner_id
  where pu.user_id=(select auth.uid())
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if v_result is null then
    raise exception 'Active Partner account not found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_my_partner_dashboard() from public, anon;
grant execute on function public.get_my_partner_dashboard() to authenticated;

comment on column public.partners.voucher_limit is
'Partner-wide issuance ceiling. 0 means unlimited; positive values are enforced from canonical Voucher row count.';