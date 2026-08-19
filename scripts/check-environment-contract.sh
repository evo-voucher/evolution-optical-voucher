#!/usr/bin/env bash
set -euo pipefail

fail(){ echo "ENVIRONMENT CONTRACT FAIL: $*" >&2; exit 1; }
pass(){ echo "OK: $*"; }

prod_config='assets/js/backend-config.js'
uat_config='uat-preview/assets/js/backend-config.js'
readiness='docs/VOUCHER-ENGINE-READINESS.md'
prod_smoke='.github/workflows/production-public-smoke.yml'
env_contract='docs/ENVIRONMENT-CONTRACT.md'
env_routing='docs/XIAOE-ENVIRONMENT-ROUTING.md'

for file in "$prod_config" "$uat_config" "$readiness" "$prod_smoke" "$env_contract" "$env_routing"; do
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

[[ "$prod_config_id" == "$readiness_id" ]] || fail "repository Production backend-config target ($prod_config_id) != current release target ($readiness_id)"
pass "Production backend-config identity matches current release contract"

grep -Fq 'cebae630fb41e7222c8ba1deed8761a044fa7f76' "$readiness" || fail 'Readiness does not preserve current Production target-change evidence'
pass 'Production target history is explicitly recorded'

grep -Eq "role:[[:space:]]*'uat'" "$uat_config" || fail "UAT preview lacks explicit role: 'uat'"
grep -Eq "authoritativeData:[[:space:]]*false" "$uat_config" || fail 'UAT preview is not explicitly marked non-authoritative'
grep -Fq "siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/uat-preview/'" "$uat_config" || fail 'UAT preview siteBase is not isolated to /uat-preview/'
pass 'UAT preview has explicit non-production deployment identity'

# Ignore comment-only documentation such as "Never place service_role here";
# fail only when privileged credential markers appear in executable/config content.
if grep -Ev '^[[:space:]]*//' "$uat_config" | grep -Eiq "service[_-]?role|sb_secret_|SUPABASE_SERVICE_ROLE_KEY"; then
  fail 'privileged credential marker found in UAT public backend config'
fi
pass 'UAT public config contains no privileged credential markers'

grep -Fq 'L1 -> DEV/source proof' "$env_routing" || fail 'environment routing lacks L1 DEV route'
grep -Fq 'L2 -> DEV/focused backend proof' "$env_routing" || fail 'environment routing lacks L2 DEV route'
grep -Fq 'L3 -> DEV + UAT targeted business-path proof' "$env_routing" || fail 'environment routing lacks L3 UAT route'
grep -Fq 'L4 -> DEV + UAT + full required regression + explicit Production gate' "$env_routing" || fail 'environment routing lacks L4 Production gate route'
grep -Fq 'Behavior Logic is not modified by this routing contract.' "$env_routing" || fail 'routing contract does not preserve first-layer boundary'
pass 'XiaoE environment routing contract is complete'

echo 'Environment contract check PASS'
