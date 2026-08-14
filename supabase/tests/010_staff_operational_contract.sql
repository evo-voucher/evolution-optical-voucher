-- Non-destructive Staff operational contract checks.
-- Run only after migrations on the verified NEW Supabase target.

select to_regprocedure('public.staff_operational_context()') as staff_operational_context,
       to_regprocedure('public.verify_voucher(text,text)') as verify_voucher,
       to_regprocedure('public.redeem_voucher(text,text,text,text)') as redeem_voucher,
       to_regprocedure('public.staff_recent_redemptions(integer)') as staff_recent_redemptions,
       to_regprocedure('public.staff_today_summary()') as staff_today_summary;

-- Expected: every column non-null.

select p.proname,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig,','),'') as proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'staff_operational_context',
    'verify_voucher',
    'redeem_voucher',
    'staff_recent_redemptions',
    'staff_today_summary'
  )
order by p.proname;

-- Expected: SECURITY DEFINER=true, search_path=public, anon=false, authenticated=true.

-- Staff must not regain direct sensitive table reads.
select table_name,privilege_type
from information_schema.table_privileges
where table_schema='public'
  and grantee='authenticated'
  and table_name in ('vouchers','redemptions','voucher_branches')
  and privilege_type in ('INSERT','UPDATE','DELETE');
-- Expected: zero rows.

-- Required runtime checks with disposable Staff identities:
-- A) staff/manager context returns only the assigned active branch;
-- B) all_branch_manager context returns active branches and requires explicit branch selection;
-- C) verify is read-only and can_redeem=false at a disallowed branch;
-- D) redeem succeeds only at an allowed active branch;
-- E) concurrent double redemption of a single-use Voucher yields one completed redemption;
-- F) staff_recent_redemptions scope: staff=self, manager=assigned branch, all_branch_manager=all branches;
-- G) suspended/removed Staff cannot use any Staff operational RPC.
