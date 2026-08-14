-- Voucher Engine v1
-- Layer above Stable Core. Voucher Type = behavior; Theme = presentation.

create table if not exists public.voucher_templates (
  id uuid primary key default gen_random_uuid(),
  template_code text not null unique,
  template_name text not null,
  voucher_category text not null,
  description text,
  status text not null default 'draft' check (status in ('draft','active','inactive','archived')),
  theme_code text not null default 'default',
  theme_config jsonb not null default '{}'::jsonb,
  current_version_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.voucher_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.voucher_templates(id) on delete restrict,
  version_no integer not null check (version_no > 0),
  version_name text,
  face_value numeric check (face_value is null or face_value >= 0),
  discount_percent numeric check (discount_percent is null or (discount_percent >= 0 and discount_percent <= 100)),
  validity_mode text not null check (validity_mode in ('fixed','days','months')),
  valid_days integer check (valid_days is null or valid_days > 0),
  valid_months integer check (valid_months is null or valid_months > 0),
  valid_from date,
  valid_until date,
  min_spend numeric check (min_spend is null or min_spend >= 0),
  max_discount numeric check (max_discount is null or max_discount >= 0),
  usage_limit integer not null default 1 check (usage_limit > 0),
  transferable boolean not null default true,
  terms_text text,
  supply_limit integer check (supply_limit is null or supply_limit >= 0),
  all_branches boolean not null default false,
  theme_override_code text,
  theme_override_config jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','active','inactive','archived')),
  effective_from timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(template_id,version_no),
  check (
    (validity_mode='fixed' and valid_until is not null)
    or (validity_mode='days' and valid_days is not null)
    or (validity_mode='months' and valid_months is not null)
  )
);

alter table public.voucher_templates
  add constraint voucher_templates_current_version_fk
  foreign key (current_version_id) references public.voucher_versions(id) on delete set null;

create table if not exists public.voucher_version_branches (
  version_id uuid not null references public.voucher_versions(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key(version_id,branch_id)
);

create table if not exists public.voucher_rules (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.voucher_versions(id) on delete cascade,
  rule_type text not null,
  operator text not null,
  rule_value jsonb not null,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now()
);

create table if not exists public.partner_voucher_access (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  template_id uuid not null references public.voucher_templates(id) on delete cascade,
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  quota_type text not null default 'allocation' check (quota_type in ('allocation','unlimited')),
  quota_limit integer check (quota_limit is null or quota_limit >= 0),
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(partner_id,template_id)
);

create table if not exists public.partner_voucher_allocations (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete restrict,
  version_id uuid not null references public.voucher_versions(id) on delete restrict,
  quantity_allocated integer not null check (quantity_allocated >= 0),
  quantity_revoked integer not null default 0 check (quantity_revoked >= 0),
  status text not null default 'active' check (status in ('active','suspended','closed')),
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (quantity_revoked <= quantity_allocated)
);

create table if not exists public.voucher_allocation_events (
  id uuid primary key default gen_random_uuid(),
  allocation_id uuid not null references public.partner_voucher_allocations(id) on delete restrict,
  partner_id uuid not null references public.partners(id) on delete restrict,
  version_id uuid not null references public.voucher_versions(id) on delete restrict,
  event_type text not null check (event_type in ('allocated','increased','revoked','restored','closed')),
  quantity integer not null check (quantity >= 0),
  reason text,
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Complete the Stable Core references now that the engine exists.
alter table public.vouchers
  add constraint vouchers_template_fk foreign key (template_id) references public.voucher_templates(id) on delete set null;
alter table public.vouchers
  add constraint vouchers_version_fk foreign key (version_id) references public.voucher_versions(id) on delete set null;
alter table public.vouchers
  add constraint vouchers_allocation_fk foreign key (allocation_id) references public.partner_voucher_allocations(id) on delete set null;

create index if not exists idx_voucher_versions_template_status on public.voucher_versions(template_id,status);
create index if not exists idx_voucher_version_branches_branch on public.voucher_version_branches(branch_id);
create index if not exists idx_voucher_rules_version_status on public.voucher_rules(version_id,status);
create index if not exists idx_partner_voucher_access_template on public.partner_voucher_access(template_id);
create index if not exists idx_partner_voucher_allocations_partner_version on public.partner_voucher_allocations(partner_id,version_id,status);
create index if not exists idx_voucher_allocation_events_allocation on public.voucher_allocation_events(allocation_id,created_at desc);
create index if not exists idx_vouchers_version on public.vouchers(version_id);

alter table public.voucher_templates enable row level security;
alter table public.voucher_versions enable row level security;
alter table public.voucher_version_branches enable row level security;
alter table public.voucher_rules enable row level security;
alter table public.partner_voucher_access enable row level security;
alter table public.partner_voucher_allocations enable row level security;
alter table public.voucher_allocation_events enable row level security;

revoke all on public.voucher_templates, public.voucher_versions, public.voucher_version_branches,
  public.voucher_rules, public.partner_voucher_access, public.partner_voucher_allocations,
  public.voucher_allocation_events from anon, authenticated;

grant select on public.voucher_templates, public.voucher_versions, public.voucher_version_branches,
  public.voucher_rules, public.partner_voucher_access, public.partner_voucher_allocations,
  public.voucher_allocation_events to authenticated;

create policy voucher_templates_read_scope on public.voucher_templates for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.partner_voucher_access pva
    where pva.template_id=voucher_templates.id
      and pva.partner_id=public.current_partner_id()
      and pva.status='active'
      and (pva.valid_from is null or pva.valid_from<=now())
      and (pva.valid_until is null or pva.valid_until>=now())
  )
);

create policy voucher_versions_read_scope on public.voucher_versions for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.partner_voucher_access pva
    where pva.template_id=voucher_versions.template_id
      and pva.partner_id=public.current_partner_id()
      and pva.status='active'
      and (pva.valid_from is null or pva.valid_from<=now())
      and (pva.valid_until is null or pva.valid_until>=now())
  )
);

create policy voucher_version_branches_read_scope on public.voucher_version_branches for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.voucher_versions vv
    join public.partner_voucher_access pva on pva.template_id=vv.template_id
    where vv.id=voucher_version_branches.version_id
      and pva.partner_id=public.current_partner_id()
      and pva.status='active'
  )
);

create policy voucher_rules_read_scope on public.voucher_rules for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1 from public.voucher_versions vv
    join public.partner_voucher_access pva on pva.template_id=vv.template_id
    where vv.id=voucher_rules.version_id
      and pva.partner_id=public.current_partner_id()
      and pva.status='active'
  )
);

create policy partner_voucher_access_read_scope on public.partner_voucher_access for select to authenticated
using (public.is_voucher_admin() or partner_id=public.current_partner_id());

create policy partner_voucher_allocations_read_scope on public.partner_voucher_allocations for select to authenticated
using (public.is_voucher_admin() or partner_id=public.current_partner_id());

create policy voucher_allocation_events_read_scope on public.voucher_allocation_events for select to authenticated
using (public.is_voucher_admin() or partner_id=public.current_partner_id());
