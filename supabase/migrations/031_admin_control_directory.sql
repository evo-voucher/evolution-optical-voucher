-- Admin control directory v1
-- Purpose: support Admin mutation UI without reintroducing direct browser table reads.
-- Read models remain explicit SECURITY DEFINER RPCs guarded by active Admin identity.

create or replace function public.admin_partner_directory()
returns table(
  partner_id uuid,
  partner_code text,
  partner_name text,
  partner_status text,
  voucher_limit integer,
  vouchers_issued bigint,
  staff_limit integer,
  partner_staff_count bigint,
  staff_access_enabled boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    p.id,
    p.partner_code,
    p.partner_name,
    p.status,
    p.voucher_limit,
    (select count(*) from public.vouchers v where v.partner_id=p.id),
    p.staff_limit,
    (select count(*) from public.partner_users pu
      where pu.partner_id=p.id
        and pu.role='partner_staff'
        and pu.removed_at is null
        and pu.status in ('active','suspended')),
    p.staff_access_enabled
  from public.partners p
  where p.status <> 'archived'
  order by p.partner_name, p.partner_code;
end;
$$;

revoke all on function public.admin_partner_directory() from public, anon;
grant execute on function public.admin_partner_directory() to authenticated;

create or replace function public.admin_active_branches()
returns table(
  branch_id uuid,
  branch_code text,
  branch_name text,
  address text,
  phone text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_voucher_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select b.id,b.branch_code,b.branch_name,b.address,b.phone
  from public.branches b
  where b.status='active'
  order by b.branch_name,b.branch_code;
end;
$$;

revoke all on function public.admin_active_branches() from public, anon;
grant execute on function public.admin_active_branches() to authenticated;

comment on function public.admin_partner_directory() is
'Admin-only Partner control read model. Canonical issued count comes from vouchers; no browser table read required.';
comment on function public.admin_active_branches() is
'Admin-only active branch directory for claim-access controls.';
