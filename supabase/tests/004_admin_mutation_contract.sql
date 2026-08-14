-- Admin mutation contract audit v1
-- Non-destructive checks for the reconstructed Voucher backend.

-- A. Canonical Admin RPCs must exist exactly once by signature.
with required(name,args) as (
  values
    ('admin_set_partner_status','p_partner_id uuid, p_status text'),
    ('admin_set_partner_voucher_limit','p_partner_id uuid, p_voucher_limit integer'),
    ('admin_set_partner_staff_limit','p_partner_id uuid, p_staff_limit integer'),
    ('admin_get_partner_claim_access','p_partner_id uuid'),
    ('admin_set_partner_claim_access','p_partner_id uuid, p_all_branches boolean, p_branch_codes text[]')
)
select r.name,r.args,count(p.oid) as matches
from required r
left join pg_proc p
  on p.proname=r.name
left join pg_namespace n
  on n.oid=p.pronamespace and n.nspname='public'
where p.oid is null or pg_get_function_identity_arguments(p.oid)=r.args
group by r.name,r.args
having count(p.oid)<>1
order by r.name;

-- Expected: zero rows.
-- B. authenticated browser role must not have direct business-table mutations.
select table_name,privilege_type
from information_schema.role_table_grants
where grantee='authenticated'
  and table_schema='public'
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
  and table_name in (
    'partners','partner_users','partner_claim_settings','partner_claim_branches',
    'vouchers','voucher_branches','redemptions',
    'partner_voucher_access','partner_voucher_allocations','voucher_allocation_events',
    'voucher_templates','voucher_versions','voucher_version_branches','voucher_rules'
  )
order by table_name,privilege_type;

-- Expected: five rows, authenticated=true, anon=false.
-- C. RPC execute exposure must be authenticated-only.
with required(name) as (
  values
    ('admin_set_partner_status'),
    ('admin_set_partner_voucher_limit'),
    ('admin_set_partner_staff_limit'),
    ('admin_get_partner_claim_access'),
    ('admin_set_partner_claim_access')
)
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
join required r on r.name=p.proname
where n.nspname='public'
order by p.proname;

-- D. Voucher-limit RPC must be the authoritative post-025 implementation.
-- Informational source check. Expected function body to reference public.vouchers.
select
  p.proname,
  position('public.vouchers' in pg_get_functiondef(p.oid))>0 as uses_vouchers_source_of_truth,
  position('p.vouchers_issued' in pg_get_functiondef(p.oid))=0 as does_not_use_cached_counter_for_decision
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='admin_set_partner_voucher_limit'
  and pg_get_function_identity_arguments(p.oid)='p_partner_id uuid, p_voucher_limit integer';
