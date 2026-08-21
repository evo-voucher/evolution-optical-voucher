# Evolution Voucher System - Commercial Load Test Suite

This suite is intentionally **not auto-targeted at Production**. Every test requires an explicit target URL and, where applicable, explicit test credentials/tokens.

## Safety rules

1. Never run write-heavy tests against Production without an isolated test tenant/environment and explicit approval.
2. Public/read-only smoke load may be run against Production only at low concurrency.
3. Voucher issuance and redemption tests must use disposable test data.
4. Same-voucher concurrency tests are intended for an isolated environment because they mutate voucher/redemption state.
5. Login load tests must use a dedicated test account and may run only when `TARGET_ENV=test` or `TARGET_ENV=development`.
6. Do not commit service-role keys, JWTs, passwords, or customer data.

## Acceptance targets

- Normal-load HTTP error rate: < 1%
- Spike-load HTTP error rate: < 2%
- Public voucher view P95: < 2s
- Login P95: < 3s
- Partner/Staff operational RPC P95: < 2s
- Redemption P95: < 3s
- Large admin reports P95: < 5s
- Double-spend: 0
- Duplicate voucher codes: 0
- Cross-tenant/branch leakage: 0
- No sustained connection exhaustion after the test stops

## Included scenarios

- `public-voucher-read.js` - low-risk read-only load against `get_public_voucher`
- `login-concurrency.js` - guarded 10 / 25 / 50 concurrent password-login test for a dedicated test account
- `same-voucher-concurrency.js` - isolated-environment double-spend test
- `mixed-peak.js` - template for mixed Partner/Staff/Customer peak traffic in a test environment

## Required environment variables

### Public voucher read

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `PUBLIC_TOKEN`

### Login concurrency

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `TEST_LOGIN_EMAIL`
- `TEST_LOGIN_PASSWORD`
- `TARGET_ENV=test` or `TARGET_ENV=development`
- optional `LOGIN_STAGE=10|25|50` (default: 10)

The login script aborts if the target environment is not explicitly `test` or `development`.

Examples:

```bash
TARGET_ENV=test LOGIN_STAGE=10 k6 run load-tests/login-concurrency.js
TARGET_ENV=test LOGIN_STAGE=25 k6 run load-tests/login-concurrency.js
TARGET_ENV=test LOGIN_STAGE=50 k6 run load-tests/login-concurrency.js
```

### Same-voucher concurrency

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `STAFF_JWT`
- `VOUCHER_CODE`
- optional `BRANCH_CODE`

### Guardrail

Write-heavy scripts require:

- `ALLOW_WRITE_LOAD_TEST=true`
- `TARGET_ENV=test` or `TARGET_ENV=development`

The script aborts if those flags are absent.

## Example

```bash
k6 run load-tests/public-voucher-read.js
```

For write tests:

```bash
ALLOW_WRITE_LOAD_TEST=true TARGET_ENV=test k6 run load-tests/same-voucher-concurrency.js
```

## Interpretation

A load test is PASS only when both performance and business invariants hold. Fast responses with duplicate redemptions, quota overruns, or cross-tenant leakage are failures.
