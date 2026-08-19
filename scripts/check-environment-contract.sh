#!/usr/bin/env bash
set -euo pipefail

fail(){ echo "ENVIRONMENT CONTRACT FAIL: $*" >&2; exit 1; }
pass(){ echo "OK: $*"; }

prod_config='assets/js/backend-config.js'
uat_config='uat-preview/assets/js/backend-config.js'
readiness='docs/VOUCHER-ENGINE-READINESS.md'
prod_smoke='.github/workflows/production-public-smoke.yml'

for file in "$prod_config" "$uat_config" "$readiness" "$prod_smoke"; do
  [[ -f "$file" ]] || fail "missing required file: $file"
done

extract_project_id(){
  sed -n "s/.*projectId:[[:space:]]*'\([^']*\)'.*/\1/p" "$1" | head -n1
}

prod_config_id="$(extract_project_id "$prod_config")"
[[ -n "$prod_config_id" ]] || fail 'production backend-config projectId missing'

readiness_id="$(sed -n 's/.*`production_target = \([^`]*\)`.*/\1/p' "$readiness" | head -n1)"
[[ -n "$readiness_id" ]] || fail 'readiness production_target missing'

smoke_id="$(sed -n "s/.*projectId: '\([^']*\)'.*/\1/p" "$prod_smoke" | head -n1)"
[[ -n "$smoke_id" ]] || fail 'production smoke expected projectId missing'

[[ "$readiness_id" == "$smoke_id" ]] || fail "readiness target ($readiness_id) != production smoke target ($smoke_id)"
pass "Readiness and Production Smoke agree on $readiness_id"

if [[ "$prod_config_id" != "$readiness_id" ]]; then
  fail "repository Production backend-config target ($prod_config_id) != documented/smoke Production target ($readiness_id). Re-verify live runtime before correcting either side."
fi
pass "Production backend-config identity matches release contract"

grep -Eq "role:[[:space:]]*'uat'" "$uat_config" || fail "UAT preview lacks explicit role: 'uat'"
grep -Eq "authoritativeData:[[:space:]]*false" "$uat_config" || fail 'UAT preview is not explicitly marked non-authoritative'
grep -Fq "siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/uat-preview/'" "$uat_config" || fail 'UAT preview siteBase is not isolated to /uat-preview/'
pass 'UAT preview has explicit non-production deployment identity'

if grep -Eiq "service[_-]?role|sb_secret_|SUPABASE_SERVICE_ROLE_KEY" "$uat_config"; then
  fail 'privileged credential marker found in UAT public backend config'
fi
pass 'UAT public config contains no privileged credential markers'

echo 'Environment contract check PASS'
