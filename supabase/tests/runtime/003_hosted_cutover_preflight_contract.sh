#!/usr/bin/env bash
set -euo pipefail

CONFIG="assets/js/backend-config.js"
READINESS="docs/VOUCHER-ENGINE-READINESS.md"
RUNBOOK="docs/HOSTED-CUTOVER-RUNBOOK.md"

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
[[ -f "$READINESS" ]] || { echo "Missing $READINESS" >&2; exit 1; }
[[ -f "$RUNBOOK" ]] || { echo "Missing $RUNBOOK" >&2; exit 1; }

if grep -Eiq "service[_-]?role[^\n]*(key|secret)|sb_secret_|SUPABASE_SERVICE_ROLE_KEY" "$CONFIG"; then
  echo "Potential service-role secret material found in frontend config" >&2
  exit 1
fi

if grep -Fq "uuqiwyqxllqsuboogbxh" "$CONFIG"; then
  echo "XiaoE AI Core must never be used as the Voucher frontend backend" >&2
  exit 1
fi

if grep -Eq "enabled:[[:space:]]*false" "$CONFIG"; then
  grep -Eq "projectId:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed projectId must be blank" >&2; exit 1; }
  grep -Eq "supabaseUrl:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed supabaseUrl must be blank" >&2; exit 1; }
  grep -Eq "publishableKey:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed publishableKey must be blank" >&2; exit 1; }
  echo "Hosted cutover preflight OK: PREPARED / fail-closed"
  exit 0
fi

grep -Eq "enabled:[[:space:]]*true" "$CONFIG" || { echo "backend-config enabled state is invalid" >&2; exit 1; }
grep -Eq "environment:[[:space:]]*'production'" "$CONFIG" || { echo "Enabled backend must declare production environment" >&2; exit 1; }
grep -Eq "projectId:[[:space:]]*'xfivcfwexcxsyiylgryn'" "$CONFIG" || { echo "Enabled backend must target canonical production project" >&2; exit 1; }
grep -Eq "supabaseUrl:[[:space:]]*'https://xfivcfwexcxsyiylgryn\.supabase\.co'" "$CONFIG" || { echo "Enabled backend must use canonical HTTPS Supabase URL" >&2; exit 1; }
grep -Eq "publishableKey:[[:space:]]*'sb_publishable_[A-Za-z0-9_-]+'" "$CONFIG" || { echo "Enabled backend must use a modern Supabase publishable key" >&2; exit 1; }
grep -Eq "siteBase:[[:space:]]*'https://evo-voucher\.github\.io/evolution-optical-voucher/'" "$CONFIG" || { echo "Enabled backend must use approved GitHub Pages siteBase" >&2; exit 1; }

grep -Fq 'cutover_state = CUTOVER_IN_PROGRESS' "$READINESS" || grep -Fq 'cutover_state = VERIFIED' "$READINESS" || { echo "Readiness must declare an approved cutover state" >&2; exit 1; }
grep -Fq 'production_target = xfivcfwexcxsyiylgryn' "$READINESS" || { echo "Readiness must record the canonical production target" >&2; exit 1; }
grep -Fq 'hosted_cutover_verified = false' "$READINESS" || grep -Fq 'hosted_cutover_verified = true' "$READINESS" || { echo "Readiness must explicitly record hosted_cutover_verified" >&2; exit 1; }
grep -Fq 'Status: CUTOVER IN PROGRESS' "$RUNBOOK" || grep -Fq 'Status: VERIFIED' "$RUNBOOK" || { echo "Runbook must declare cutover state" >&2; exit 1; }
grep -Fq 'canonical reconstruction' "$RUNBOOK" || { echo "Runbook must record canonical reconstruction route" >&2; exit 1; }
grep -Fq 'xfivcfwexcxsyiylgryn' "$RUNBOOK" || { echo "Runbook must record canonical production project" >&2; exit 1; }
grep -Fq 'uuqiwyqxllqsuboogbxh' "$RUNBOOK" || { echo "Runbook must retain XiaoE AI Core boundary" >&2; exit 1; }
grep -Fq 'Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption' "$RUNBOOK" || { echo "Runbook must retain full production smoke chain" >&2; exit 1; }

echo "Hosted cutover preflight OK: canonical production target, publishable-only browser config, XiaoE boundary preserved"
