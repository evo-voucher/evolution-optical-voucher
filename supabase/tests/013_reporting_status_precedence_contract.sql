-- Non-destructive reporting status precedence checks.
-- Run only after migrations on the verified NEW Supabase target.

select to_regprocedure('public.admin_dashboard_summary()') as admin_dashboard_summary,
       to_regprocedure('public.partner_voucher_summary()') as partner_voucher_summary;

-- Both summary functions must document/use mutually exclusive canonical precedence.
select p.proname,
       position('v.status<>''revoked''' in replace(pg_get_functiondef(p.oid),' ',''))>0 as excludes_revoked_from_other_buckets,
       position('usage_count>=v.usage_limit' in replace(pg_get_functiondef(p.oid),' ',''))>0 as redeemed_uses_usage_count,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig,','),'') as proconfig
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('admin_dashboard_summary','partner_voucher_summary')
order by p.proname;

-- Review expectations:
-- 1) SECURITY DEFINER=true and search_path=public.
-- 2) Revoked vouchers are counted only in revoked bucket.
-- 3) Expired vouchers are excluded from redeemed bucket.
-- 4) Redeemed bucket contains only non-revoked, non-expired vouchers at usage limit.
-- 5) Active bucket contains only active, unexpired vouchers below usage limit.

-- Required runtime fixture checks:
-- A) active/unexpired/below-limit voucher -> active only;
-- B) fully-used voucher -> redeemed only;
-- C) expired active voucher -> expired only;
-- D) revoked fully-used voucher -> revoked only, not redeemed;
-- E) revoked expired voucher -> revoked only, not expired;
-- F) for each scope, active+redeemed+expired+revoked = issued_total/vouchers_total when fixture uses only canonical statuses.