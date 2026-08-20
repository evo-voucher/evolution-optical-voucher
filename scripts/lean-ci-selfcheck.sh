#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "index.html"
  "admin-dashboard.html"
  "admin-core.html"
  "admin-staff.html"
  "experience/admin-v2.html"
  "experience/partner-v2.html"
)

for file in "${required_files[@]}"; do
  test -s "$file" || { echo "Missing or empty critical file: $file"; exit 1; }
done

migrations="supabase/migrations"
test -d "$migrations" || { echo "Missing migrations directory"; exit 1; }

required_contracts=(
  "issue_engine_voucher"
  "admin_engine_revoke_unissued"
  "admin_dashboard_summary"
  "purge_unredeemed_vouchers"
  "_cleanup_stale_voucher_data"
)

for contract in "${required_contracts[@]}"; do
  grep -Rqs --include='*.sql' "$contract" "$migrations" || {
    echo "Missing core database contract: $contract"
    exit 1
  }
done

cleanup_file=$(grep -Ril --include='*.sql' "create or replace function public._cleanup_stale_voucher_data" "$migrations" | sort | tail -n 1)
test -n "$cleanup_file" || { echo "Unified cleanup engine definition not found"; exit 1; }

grep -q "public._cleanup_stale_voucher_data" "$cleanup_file" || {
  echo "Cleanup wrapper is no longer tied to the unified engine"
  exit 1
}

grep -q "not exists(select 1 from public.redemptions" "$cleanup_file" || {
  echo "Cleanup no longer visibly protects redemption history"
  exit 1
}

if grep -RniE --include='*.html' --include='*.js' \
  '(SUPABASE_SERVICE_ROLE_KEY|service_role[[:space:]]*[:=][[:space:]]*["'"''][A-Za-z0-9._-]{20,})' \
  . --exclude-dir=.git; then
  echo "Potential service-role secret found in browser-delivered code"
  exit 1
fi

for file in "${required_files[@]}"; do
  grep -qi '<html' "$file" || { echo "$file: missing <html>"; exit 1; }
  grep -qi '</html>' "$file" || { echo "$file: missing </html>"; exit 1; }
done

echo "Critical Evolution Voucher regression guards passed."
