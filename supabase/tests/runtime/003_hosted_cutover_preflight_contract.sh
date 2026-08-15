#!/usr/bin/env bash
set -euo pipefail

CONFIG="assets/js/backend-config.js"
READINESS="docs/VOUCHER-ENGINE-READINESS.md"

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
[[ -f "$READINESS" ]] || { echo "Missing $READINESS" >&2; exit 1; }

# Until a new Voucher target is explicitly approved, the frontend must stay fail-closed.
grep -Eq "enabled:[[:space:]]*false" "$CONFIG" || { echo "backend-config must remain disabled before hosted cutover approval" >&2; exit 1; }
grep -Eq "projectId:[[:space:]]*''" "$CONFIG" || { echo "projectId must remain blank before hosted target approval" >&2; exit 1; }
grep -Eq "supabaseUrl:[[:space:]]*''" "$CONFIG" || { echo "supabaseUrl must remain blank before hosted target approval" >&2; exit 1; }
grep -Eq "publishableKey:[[:space:]]*''" "$CONFIG" || { echo "publishableKey must remain blank before hosted target approval" >&2; exit 1; }

# Known non-target project IDs must never be wired into the Voucher frontend configuration.
for forbidden in hukihbcyyqhanaqrizvm uuqiwyqxllqsuboogbxh; do
  if grep -Fq "$forbidden" "$CONFIG"; then
    echo "Forbidden Supabase project ID present in frontend config: $forbidden" >&2
    exit 1
  fi
done

# Public code must not contain service-role credentials or obvious secret placeholders.
if grep -Eiq "service[_-]?role[^\n]*(key|secret)|sb_secret_|SUPABASE_SERVICE_ROLE_KEY" "$CONFIG"; then
  echo "Potential service-role secret material found in frontend config" >&2
  exit 1
fi

# Readiness truth must remain explicit until a real hosted target passes production E2E.
grep -Fq 'hosted_cutover_verified = false' "$READINESS" || { echo "Readiness doc must explicitly keep hosted_cutover_verified = false" >&2; exit 1; }
grep -Fq 'legacy production must not be mutated' "$READINESS" || { echo "Readiness doc must retain legacy-production protection" >&2; exit 1; }

echo "Hosted cutover preflight contract OK: frontend fail-closed, forbidden targets absent, hosted cutover still false"
