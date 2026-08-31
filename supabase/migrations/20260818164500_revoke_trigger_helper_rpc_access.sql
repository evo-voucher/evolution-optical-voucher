-- Revoke direct RPC access from the trigger helper when it exists.
-- Fresh canonical rebuilds may reach this historical hardening migration before
-- attach_voucher_customer() is introduced, in which case there is nothing to revoke.

do $migration$
begin
  if to_regprocedure('public.attach_voucher_customer()') is not null then
    revoke all on function public.attach_voucher_customer() from public, anon, authenticated;
  end if;
end
$migration$;
