#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
from pathlib import Path

root = Path('.')
manifest_path = root / 'recovery' / 'system-init-manifest.json'
if not manifest_path.is_file():
    raise SystemExit('Recovery manifest missing: recovery/system-init-manifest.json')

manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

required_top = {
    'schema_version', 'name', 'backup_type', 'live_business_data_included',
    'secrets_included', 'sources', 'required_security_invariants',
    'recovery_acceptance', 'cutover_flags'
}
missing = sorted(required_top - set(manifest))
if missing:
    raise SystemExit(f'Recovery manifest missing keys: {missing}')

if manifest['backup_type'] != 'clean_system_initialization':
    raise SystemExit('backup_type must remain clean_system_initialization')
if manifest['live_business_data_included'] is not False:
    raise SystemExit('Clean initialization archive must not include live business data')
if manifest['secrets_included'] is not False:
    raise SystemExit('Recovery archive must not include secrets')

sources = manifest['sources']
for key in (
    'database_migrations', 'edge_functions', 'supabase_local_config',
    'frontend_root', 'runtime_tests', 'ci_workflows', 'recovery_document'
):
    value = sources.get(key)
    if not value:
        raise SystemExit(f'Missing recovery source: {key}')
    path = root / value
    if not path.exists():
        raise SystemExit(f'Recovery source does not exist: {key} -> {value}')

migrations = sorted((root / sources['database_migrations']).glob('*.sql'))
if not migrations:
    raise SystemExit('No Supabase migrations found in recovery source')

functions_dir = root / sources['edge_functions']
function_entries = [p for p in functions_dir.iterdir() if p.is_dir()]
if not function_entries:
    raise SystemExit('No Edge Function directories found in recovery source')

required_invariants = {
    'frontend_fail_closed_until_explicit_target_config',
    'service_role_server_only',
    'tenant_identity_auth_derived',
    'rls_and_narrow_rpc_boundaries_preserved',
    'issued_voucher_snapshots_immutable',
    'legacy_production_not_modified_during_recovery',
    'xiaoe_ai_core_never_receives_voucher_migrations',
}
actual_invariants = set(manifest['required_security_invariants'])
missing_invariants = sorted(required_invariants - actual_invariants)
if missing_invariants:
    raise SystemExit(f'Recovery manifest lost security invariants: {missing_invariants}')

acceptance = manifest['recovery_acceptance']
required_acceptance = {
    'migrations_apply', 'sql_contracts_pass', 'gotrue_core_flow_pass',
    'edge_trusted_boundary_pass', 'partner_staff_lifecycle_pass',
    'admin_controls_pass', 'browser_e2e_pass', 'migration_state_pass',
    'clean_teardown_pass', 'hosted_target_smoke_required_for_production_cutover'
}
for key in required_acceptance:
    if acceptance.get(key) is not True:
        raise SystemExit(f'Recovery acceptance gate must remain true: {key}')

flags = manifest['cutover_flags']
if flags.get('hosted_cutover_verified') is not False:
    raise SystemExit('Recovery manifest must not claim hosted cutover before hosted verification')
if flags.get('legacy_production_touched') is not False:
    raise SystemExit('Recovery manifest must preserve legacy production untouched flag')

print(f'Recovery manifest contract OK: {len(migrations)} migrations, {len(function_entries)} Edge Function directories')
PY
