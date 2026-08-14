-- Non-destructive Partner-wide voucher quota contract checks.
-- Run only after migrations on the verified NEW Supabase target.

select to_regprocedure('public.guard_partner_global_voucher_quota()') as quota_guard,
       to_regprocedure('public.admin_set_partner_voucher_limit(uuid,integer)') as admin_set_limit,
       to_regprocedure('public.get_my_partner_dashboard()') as partner_dashboard;

-- Expected: all three functions exist.

select tgname,tgrelid::regclass as table_name
from pg_trigger
where not tgisinternal
  and tgname='vouchers_guard_global_partner_quota';
-- Expected: exactly one trigger on public.vouchers.

select position('v_limit=0' in replace(pg_get_functiondef('public.guard_partner_global_voucher_quota()'::regprocedure),' ',''))>0 as zero_is_unlimited_in_guard,
       position('p_voucher_limit<>0' in replace(pg_get_functiondef('public.admin_set_partner_voucher_limit(uuid,integer)'::regprocedure),' ',''))>0 as zero_is_unlimited_in_admin_setter,
       position('voucher_limit_unlimited' in pg_get_functiondef('public.get_my_partner_dashboard()'::regprocedure))>0 as dashboard_exposes_unlimited_flag;

-- Runtime behavioral checks required with disposable data:
-- A) voucher_limit=0 allows issuance when allocation/version capacity exists.
-- B) changing a Partner with existing vouchers to voucher_limit=0 succeeds.
-- C) positive voucher_limit=N allows at most N canonical Voucher rows for that Partner.
-- D) concurrent issuance attempts at N-1 cannot create more than one final Voucher.
-- E) all issuance entrypoints (Engine and compatibility wrappers) are stopped by the same INSERT-boundary guard.
-- F) dashboard returns voucher_limit_unlimited=true and remaining=null for voucher_limit=0.
-- G) positive limit lower than already-issued canonical Voucher count is rejected.
-- H) partners.vouchers_issued may differ from count(vouchers) without weakening quota enforcement.