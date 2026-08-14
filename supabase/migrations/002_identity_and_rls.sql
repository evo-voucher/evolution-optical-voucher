-- Evolution Voucher Identity + RLS v1
-- Target: new blank Supabase project only.

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text,
  status text not null default 'active' check (status in ('active','suspended','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;

drop function if exists public.is_voucher_admin();
create function public.is_voucher_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users a
    where a.user_id = (select auth.uid())
      and a.status = 'active'
  );
$$;

revoke all on function public.is_voucher_admin() from public, anon;
grant execute on function public.is_voucher_admin() to authenticated;

drop function if exists public.current_partner_id();
create function public.current_partner_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select pu.partner_id
  from public.partner_users pu
  join public.partners p on p.id = pu.partner_id
  where pu.user_id = (select auth.uid())
    and pu.status = 'active'
    and pu.removed_at is null
    and p.status = 'active'
  limit 1;
$$;
revoke all on function public.current_partner_id() from public, anon;
grant execute on function public.current_partner_id() to authenticated;

drop function if exists public.current_partner_role();
create function public.current_partner_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select pu.role
  from public.partner_users pu
  join public.partners p on p.id = pu.partner_id
  where pu.user_id = (select auth.uid())
    and pu.status = 'active'
    and pu.removed_at is null
    and p.status = 'active'
  limit 1;
$$;
revoke all on function public.current_partner_role() from public, anon;
grant execute on function public.current_partner_role() to authenticated;

drop function if exists public.current_staff_branch_id();
create function public.current_staff_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select su.branch_id
  from public.staff_users su
  where su.user_id = (select auth.uid())
    and su.status = 'active'
  limit 1;
$$;
revoke all on function public.current_staff_branch_id() from public, anon;
grant execute on function public.current_staff_branch_id() to authenticated;

drop function if exists public.current_staff_role();
create function public.current_staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select su.role
  from public.staff_users su
  where su.user_id = (select auth.uid())
    and su.status = 'active'
  limit 1;
$$;
revoke all on function public.current_staff_role() from public, anon;
grant execute on function public.current_staff_role() to authenticated;

-- Read grants. Writes are intentionally routed through controlled RPCs.
grant select on public.partners, public.branches, public.partner_users,
  public.staff_users, public.partner_claim_settings, public.partner_claim_branches,
  public.vouchers, public.voucher_branches, public.redemptions, public.admin_audit_log,
  public.admin_users to authenticated;

-- Consolidated RLS policies: one policy per table/action to avoid the legacy
-- multiple-permissive-policy pattern.
create policy admin_users_read_self_or_admin
on public.admin_users for select to authenticated
using (user_id = (select auth.uid()) or public.is_voucher_admin());

create policy partners_read_scope
on public.partners for select to authenticated
using (
  public.is_voucher_admin()
  or id = public.current_partner_id()
);

create policy partner_users_read_scope
on public.partner_users for select to authenticated
using (
  public.is_voucher_admin()
  or user_id = (select auth.uid())
  or (
    partner_id = public.current_partner_id()
    and public.current_partner_role() = 'partner_admin'
  )
);

create policy staff_users_read_scope
on public.staff_users for select to authenticated
using (
  public.is_voucher_admin()
  or user_id = (select auth.uid())
  or public.current_staff_role() = 'all_branch_manager'
);

create policy branches_read_scope
on public.branches for select to authenticated
using (
  public.is_voucher_admin()
  or status = 'active'
);

create policy partner_claim_settings_read_scope
on public.partner_claim_settings for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
);

create policy partner_claim_branches_read_scope
on public.partner_claim_branches for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
);

create policy vouchers_read_scope
on public.vouchers for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
  or exists (
    select 1
    from public.redemptions r
    where r.voucher_id = vouchers.id
      and r.staff_user_id = (select auth.uid())
  )
);

create policy voucher_branches_read_scope
on public.voucher_branches for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.vouchers v
    where v.id = voucher_branches.voucher_id
      and v.partner_id = public.current_partner_id()
  )
  or exists (
    select 1 from public.staff_users su
    where su.user_id = (select auth.uid())
      and su.status = 'active'
      and (su.role = 'all_branch_manager' or su.branch_id = voucher_branches.branch_id)
  )
);

create policy redemptions_read_scope
on public.redemptions for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
  or staff_user_id = (select auth.uid())
  or public.current_staff_role() = 'all_branch_manager'
);

create policy admin_audit_log_read_admin
on public.admin_audit_log for select to authenticated
using (public.is_voucher_admin());

-- No INSERT/UPDATE/DELETE policies here by design. Mutating actions are RPC-only.
