# Admin B5 UAT Checklist

Branch: `experience/admin-b-ui`

## Static / code-path checks

- [x] Portal B -> Admin B5 (`experience/admin-b.html`)
- [x] Portal B -> Voucher Engine (`../voucher-engine.html`)
- [x] Portal B -> Partner launcher (`../partner-launch.html`)
- [x] Portal B -> Staff launcher (`../staff-launch.html`)
- [x] Admin B5 Main -> Portal B (`portal-b.html`)
- [x] Admin B5 Sign Out performs local Supabase sign-out before returning to Admin launcher
- [x] Admin Tools -> Partner uses existing production Admin operation page
- [x] Admin Tools -> Staff uses existing `admin-staff.html`
- [x] Summary uses `admin_dashboard_summary()`
- [x] Voucher Reports uses `admin_voucher_report(...)`
- [x] Redemption Reports uses `admin_redemption_report(...)`
- [x] Branch Address & Staff Info uses `admin_branch_directory()` + `admin_staff_directory()`
- [x] Partner Issues uses `admin_partner_issue_period_stats()`
- [x] Admin Settings UAT is read-only
- [x] Customer requirements read via `customer_field_requirements()`
- [x] District list read via `admin_customer_district_directory()`
- [x] No Settings mutation RPC is invoked by the B5 UAT page
- [x] Reports are view-only in B5
- [x] `main` is not modified by B5 work

## Manual mobile click checks still required

- [ ] Open Portal B and tap Admin
- [ ] Confirm existing Admin session is reused correctly
- [ ] Confirm Summary values render on iPhone
- [ ] Open Voucher Reports and return
- [ ] Open Redemption Reports and return
- [ ] Open Branch Address & Staff Info and return
- [ ] Open Partner Issues and confirm Today / Week / Month values
- [ ] Open Admin Settings and confirm controls are disabled/read-only
- [ ] Tap Partner and confirm existing operation page opens
- [ ] Tap Staff and confirm existing Staff management page opens
- [ ] Tap Main and confirm return to Portal B
- [ ] Tap Sign Out and confirm the Admin session ends

## Safety status

B5 reads live production Admin RPC data but does not expose any new production mutation path. Production UI and `main` remain unchanged during UAT.
