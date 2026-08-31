-- Converge fresh rebuild staff schema with the current hardened production shape.

alter table public.staff_users
  add column if not exists login_email text;

create unique index if not exists staff_users_single_active_branch_manager
  on public.staff_users (branch_id)
  where status = 'active'
    and role = 'manager'
    and branch_id is not null;
