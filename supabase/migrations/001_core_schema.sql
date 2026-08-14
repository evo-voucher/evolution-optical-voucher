-- Evolution Voucher Core Schema v1
-- DRAFT ONLY. Do not apply to legacy production project.
-- Target: new blank Supabase project.

create extension if not exists pgcrypto;

create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  partner_code text not null unique,
  partner_name text not null,
  contact_person text,
  contact_phone text,
  voucher_limit integer not null default 0 check (voucher_limit >= 0),
  staff_limit integer not null default 0 check (staff_limit >= 0),
  staff_access_enabled boolean not null default false,
  status text not null default 'active' check (status in ('active','suspended','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  branch_code text not null unique,
  branch_name text not null,
  address text,
  phone text,
  status text not null default 'active' check (status in ('active','inactive','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.partner_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  partner_id uuid not null references public.partners(id) on delete restrict,
  role text not null check (role in ('partner_admin','partner_staff')),
  status text not null default 'active' check (status in ('active','suspended','removed')),
  staff_name text,
  login_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz
);

create table if not exists public.staff_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  staff_name text not null,
  role text not null check (role in ('staff','manager','all_branch_manager')),
  status text not null default 'active' check (status in ('active','suspended','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.partner_claim_settings (
  partner_id uuid primary key references public.partners(id) on delete cascade,
  all_branches boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.partner_claim_branches (
  partner_id uuid not null references public.partners(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (partner_id, branch_id)
);

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  voucher_code text not null unique,
  public_token uuid not null unique default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  customer_name text not null,
  customer_phone text,
  voucher_type text not null,
  status text not null default 'active' check (status in ('active','redeemed','expired','revoked')),
  expiry_date date not null,
  issued_at timestamptz not null default now(),
  activated_at timestamptz not null default now(),
  issued_by_user_id uuid references auth.users(id) on delete set null,
  issued_by_name text,
  all_branches boolean not null default false,
  usage_limit integer not null default 1 check (usage_limit > 0),
  usage_count integer not null default 0 check (usage_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  template_id uuid,
  version_id uuid,
  allocation_id uuid,
  revoked_at timestamptz,
  revoked_by_user_id uuid references auth.users(id) on delete set null,
  revoke_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (usage_count <= usage_limit)
);

create table if not exists public.voucher_branches (
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (voucher_id, branch_id)
);

create table if not exists public.redemptions (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete restrict,
  partner_id uuid not null references public.partners(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  staff_user_id uuid not null references auth.users(id) on delete restrict,
  staff_name_snapshot text not null,
  redeem_method text not null check (redeem_method in ('qr','manual_code','admin')),
  status text not null default 'completed' check (status in ('completed','reversed')),
  redeemed_at timestamptz not null default now(),
  notes text,
  reversed_at timestamptz,
  reversed_by_user_id uuid references auth.users(id) on delete set null,
  reversed_by_name text,
  reverse_reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_name text,
  action_type text not null,
  entity_type text not null,
  entity_id text,
  partner_id uuid references public.partners(id) on delete set null,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_partner_users_partner_status
  on public.partner_users(partner_id, status);

create index if not exists idx_staff_users_branch_status
  on public.staff_users(branch_id, status);

create index if not exists idx_vouchers_partner_issued
  on public.vouchers(partner_id, issued_at desc);

create index if not exists idx_vouchers_status_expiry
  on public.vouchers(status, expiry_date);

create index if not exists idx_voucher_branches_branch
  on public.voucher_branches(branch_id);

create index if not exists idx_redemptions_voucher
  on public.redemptions(voucher_id);

create index if not exists idx_redemptions_partner_time
  on public.redemptions(partner_id, redeemed_at desc);

create index if not exists idx_redemptions_branch_time
  on public.redemptions(branch_id, redeemed_at desc);

create index if not exists idx_redemptions_staff_time
  on public.redemptions(staff_user_id, redeemed_at desc);

-- No blanket unique(voucher_id) constraint here because the core supports future multi-use vouchers.
-- Single-use and multi-use concurrency are both enforced inside the redeem RPC by locking
-- the voucher row and validating usage_count < usage_limit before inserting redemption.

-- RLS is enabled immediately. Policies are defined in the next migration.
alter table public.partners enable row level security;
alter table public.branches enable row level security;
alter table public.partner_users enable row level security;
alter table public.staff_users enable row level security;
alter table public.partner_claim_settings enable row level security;
alter table public.partner_claim_branches enable row level security;
alter table public.vouchers enable row level security;
alter table public.voucher_branches enable row level security;
alter table public.redemptions enable row level security;
alter table public.admin_audit_log enable row level security;

-- Default-deny until policies/RPCs are installed.
revoke all on public.partners from anon, authenticated;
revoke all on public.branches from anon, authenticated;
revoke all on public.partner_users from anon, authenticated;
revoke all on public.staff_users from anon, authenticated;
revoke all on public.partner_claim_settings from anon, authenticated;
revoke all on public.partner_claim_branches from anon, authenticated;
revoke all on public.vouchers from anon, authenticated;
revoke all on public.voucher_branches from anon, authenticated;
revoke all on public.redemptions from anon, authenticated;
revoke all on public.admin_audit_log from anon, authenticated;