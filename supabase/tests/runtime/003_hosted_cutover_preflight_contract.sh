#!/usr/bin/env bash
set -euo pipefail

CONFIG="assets/js/backend-config.js"
READINESS="docs/VOUCHER-ENGINE-READINESS.md"
RUNBOOK="docs/HOSTED-CUTOVER-RUNBOOK.md"

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
[[ -f "$READINESS" ]] || { echo "Missing $READINESS" >&2; exit 1; }
[[ -f "$RUNBOOK" ]] || { echo "Missing $RUNBOOK" >&2; exit 1; }

# Public code must never contain privileged Supabase credentials.
if grep -Eiq "service[_-]?role[^\n]*(key|secret)|sb_secret_|SUPABASE_SERVICE_ROLE_KEY" "$CONFIG"; then
  echo "Potential service-role secret material found in frontend config" >&2
  exit 1
fi

# Voucher frontend must never target XiaoE AI Core.
if grep -Fq "uuqiwyqxllqsuboogbxh" "$CONFIG"; then
  echo "XiaoE AI Core must never be used as the Voucher frontend backend" >&2
  exit 1
fi

if grep -Eq "enabled:[[:space:]]*false" "$CONFIG"; then
  # PREPARED / fail-closed state.
  grep -Eq "projectId:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed projectId must be blank" >&2; exit 1; }
  grep -Eq "supabaseUrl:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed supabaseUrl must be blank" >&2; exit 1; }
  grep -Eq "publishableKey:[[:space:]]*''" "$CONFIG" || { echo "Fail-closed publishableKey must be blank" >&2; exit 1; }
  echo "Hosted cutover preflight OK: PREPARED / fail-closed"
  exit 0
fi

# CUTOVER_IN_PROGRESS / VERIFIED production state.
grep -Eq "enabled:[[:space:]]*true" "$CONFIG" || { echo "backend-config enabled state is invalid" >&2; exit 1; }
grep -Eq "environment:[[:space:]]*'production'" "$CONFIG" || { echo "Enabled backend must declare production environment" >&2; exit 1; }
grep -Eq "projectId:[[:space:]]*'hukihbcyyqhanaqrizvm'" "$CONFIG" || { echo "Enabled backend must target approved production project" >&2; exit 1; }
grep -Eq "supabaseUrl:[[:space:]]*'https://hukihbcyyqhanaqrizvm\.supabase\.co'" "$CONFIG" || { echo "Enabled backend must use approved HTTPS Supabase URL" >&2; exit 1; }
grep -Eq "publishableKey:[[:space:]]*'sb_publishable_[A-Za-z0-9_-]+'" "$CONFIG" || { echo "Enabled backend must use a modern Supabase publishable key" >&2; exit 1; }
grep -Eq "siteBase:[[:space:]]*'https://evo-voucher\.github\.io/evolution-optical-voucher/'" "$CONFIG" || { echo "Enabled backend must use approved GitHub Pages siteBase" >&2; exit 1; }

# State and runbook must explicitly describe production convergence.
grep -Fq 'cutover_state = CUTOVER_IN_PROGRESS' "$READINESS" || grep -Fq 'cutover_state = VERIFIED' "$READINESS" || { echo "Readiness must declare an approved cutover state" >&2; exit 1; }
grep -Fq 'production_target = hukihbcyyqhanaqrizvm' "$READINESS" || { echo "Readiness must record the approved production target" >&2; exit 1; }
grep -Fq 'hosted_cutover_verified = false' "$READINESS" || grep -Fq 'hosted_cutover_verified = true' "$READINESS" || { echo "Readiness must explicitly record hosted_cutover_verified" >&2; exit 1; }
grep -Fq 'Status: CUTOVER IN PROGRESS' "$RUNBOOK" || grep -Fq 'Status: VERIFIED' "$RUNBOOK" || { echo "Runbook must declare cutover state" >&2; exit 1; }
grep -Fq 'existing-production convergence' "$RUNBOOK" || { echo "Runbook must record existing-production convergence route" >&2; exit 1; }
grep -Fq 'hukihbcyyqhanaqrizvm' "$RUNBOOK" || { echo "Runbook must record production project" >&2; exit 1; }
grep -Fq 'uuqiwyqxllqsuboogbxh' "$RUNBOOK" || { echo "Runbook must retain XiaoE AI Core boundary" >&2; exit 1; }
grep -Fq 'Admin setup/allocation -> Partner issue -> WhatsApp share -> customer public Voucher -> Evolution Staff redeem -> Admin record reflects redemption' "$RUNBOOK" || { echo "Runbook must retain full production smoke chain" >&2; exit 1; }

echo "Hosted cutover preflight OK: approved production target, publishable-only browser config, XiaoE boundary preserved"
