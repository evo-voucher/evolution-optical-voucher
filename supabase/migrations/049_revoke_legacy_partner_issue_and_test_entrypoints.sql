revoke execute on function public.issue_partner_voucher(text,text,text,date) from authenticated;
revoke execute on function public.create_partner_voucher_controlled(text,text,text,text,date) from authenticated;
revoke execute on function public.delete_my_test_voucher(text) from authenticated;

comment on function public.issue_partner_voucher(text,text,text,date) is
'Legacy core_v1 issuance path retained for rollback/source history only; authenticated execution revoked. Canonical Partner issuance is issue_engine_voucher().';

comment on function public.create_partner_voucher_controlled(text,text,text,text,date) is
'Legacy single-voucher compatibility entrypoint retained for rollback/source history only; authenticated execution revoked. The stale p_customer_ic argument is not stored.';

comment on function public.delete_my_test_voucher(text) is
'Test-only TEST001 cleanup function retained for rollback/source history; authenticated production execution revoked.';
