-- Staff direct-read boundary hardening v1
-- Staff operational access to Voucher/Redemption detail is served through
-- dedicated SECURITY DEFINER RPCs (verify_voucher, redeem_voucher,
-- staff_recent_redemptions, staff_today_summary). Direct table SELECT is not
-- required and can expose more relational data than the Staff UI needs.
--
-- Partner remains able to read only its own tenant rows; Admin remains the only
-- cross-Partner table-reading operational realm.

-- Voucher rows: Admin or owning Partner only.
drop policy if exists vouchers_read_scope on public.vouchers;
create policy vouchers_read_scope
on public.vouchers for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
);

-- Redemption rows: Admin or owning Partner only.
-- Staff history must use staff_recent_redemptions(), whose server-side predicate
-- scopes staff / branch manager / all-branch-manager correctly.
drop policy if exists redemptions_read_scope on public.redemptions;
create policy redemptions_read_scope
on public.redemptions for select to authenticated
using (
  public.is_voucher_admin()
  or partner_id = public.current_partner_id()
);

-- Voucher branch mappings: Admin or owning Partner only.
-- Staff Verify/Redeem RPCs evaluate branch eligibility internally.
drop policy if exists voucher_branches_read_scope on public.voucher_branches;
create policy voucher_branches_read_scope
on public.voucher_branches for select to authenticated
using (
  public.is_voucher_admin()
  or exists (
    select 1
    from public.vouchers v
    where v.id = voucher_branches.voucher_id
      and v.partner_id = public.current_partner_id()
  )
);

comment on table public.redemptions is
'Sensitive transaction history. Direct SELECT is Admin/owning-Partner only; Staff uses scoped reporting RPCs.';

comment on table public.voucher_branches is
'Redemption branch mapping. Direct SELECT is Admin/owning-Partner only; Staff eligibility is evaluated by Verify/Redeem RPCs.';
