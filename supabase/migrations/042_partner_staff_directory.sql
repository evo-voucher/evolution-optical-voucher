-- Partner Staff directory v1
-- Read model for Partner Admin UI. Tenant is derived from auth.uid(); no partner_id input.

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
    and pu.role='partner_admin'
    and pu.status='active'
    and pu.removed_at is null
    and p.status='active'
  limit 1;

  if v_partner_id is null then
    raise exception 'Active Partner Admin access required';
  end if;

  return query
  select pu.id,pu.user_id,pu.staff_name,pu.login_email,pu.status,
         pu.created_at,pu.updated_at,pu.removed_at
  from public.partner_users pu
  where pu.partner_id=v_partner_id
    and pu.role='partner_staff'
  order by (pu.removed_at is not null), lower(coalesce(pu.staff_name,'')), pu.created_at;
end;
$$;

revoke all on function public.partner_staff_directory() from public, anon;
grant execute on function public.partner_staff_directory() to authenticated;

comment on function public.partner_staff_directory() is
'Partner Admin scoped Staff directory. Derives tenant from auth.uid(); exposes no cross-tenant selector and performs no mutations.';
