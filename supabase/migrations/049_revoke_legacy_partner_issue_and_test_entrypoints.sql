-- Canonical Partner issuance is issue_engine_voucher().
-- Remove obsolete single-voucher, compatibility and test-only entrypoints from the rebuild end state.

drop function if exists public.issue_partner_voucher(text,text,text,date);
drop function if exists public.create_partner_voucher_controlled(text,text,text,text,date);
drop function if exists public.create_partner_multi_voucher_controlled(uuid,text,text);
drop function if exists public.delete_my_test_voucher(text);
