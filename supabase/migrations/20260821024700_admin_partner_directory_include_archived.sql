-- Admin Partner directory must include archived records so Admin can find and restore them.
-- Scope: read model only. No Partner rows, permissions, voucher history, or status mutation logic are changed.

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
    (select count(*)
       from public.partner_users pu
      where pu.partner_id=p.id
        and lower(coalesce(pu.role,''))='partner_staff'
        and pu.removed_at is null
        and lower(coalesce(pu.status,''))<>'removed'),
    p.staff_access_enabled
  from public.partners p
  where upper(coalesce(p.partner_code,''))<>'ADMIN'
  order by
    case lower(coalesce(p.status,''))
      when 'active' then 0
      when 'suspended' then 1
      when 'archived' then 2
      else 3
    end,
    p.partner_name,
    p.partner_code;
end;
$$;

revoke all on function public.admin_partner_directory() from public, anon;
grant execute on function public.admin_partner_directory() to authenticated;

comment on function public.admin_partner_directory() is
'Admin-only Partner control directory. Includes archived Partners for restore workflows; excludes internal ADMIN pseudo-partner.';
