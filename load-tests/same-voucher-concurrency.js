import http from 'k6/http';
import { check, fail } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const successCount = new Counter('redeem_success_count');
const businessErrors = new Rate('business_errors');

const baseUrl = __ENV.SUPABASE_URL;
const anonKey = __ENV.SUPABASE_ANON_KEY;
const staffJwt = __ENV.STAFF_JWT;
const voucherCode = __ENV.VOUCHER_CODE;
const branchCode = __ENV.BRANCH_CODE || null;
const allowWrite = __ENV.ALLOW_WRITE_LOAD_TEST === 'true';
const targetEnv = (__ENV.TARGET_ENV || '').toLowerCase();

if (!allowWrite || !['test', 'development'].includes(targetEnv)) {
  throw new Error('Write load test blocked. Set ALLOW_WRITE_LOAD_TEST=true and TARGET_ENV=test|development.');
}
if (!baseUrl || !anonKey || !staffJwt || !voucherCode) {
  throw new Error('SUPABASE_URL, SUPABASE_ANON_KEY, STAFF_JWT and VOUCHER_CODE are required');
}

export const options = {
  scenarios: {
    double_spend_guard: {
      executor: 'shared-iterations',
      vus: 10,
      iterations: 10,
      maxDuration: '20s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<3000'],
    business_errors: ['rate<0.90'],
  },
};

export default function () {
  const url = `${baseUrl}/rest/v1/rpc/redeem_voucher`;
  const payload = JSON.stringify({
    p_voucher_code: voucherCode,
    p_notes: 'load-test',
    p_branch_code: branchCode,
    p_redeem_method: 'qr',
  });

  const res = http.post(url, payload, {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${staffJwt}`,
      'Content-Type': 'application/json',
    },
  });

  let body;
  try { body = res.json(); } catch (_) { body = null; }

  const isSuccess = res.status === 200 && body && body.success === true;
  if (isSuccess) successCount.add(1);
  businessErrors.add(!isSuccess);

  check(res, {
    'response is controlled': (r) => r.status === 200,
    'business response returned': () => body && typeof body.success === 'boolean',
  });
}

export function handleSummary(data) {
  const successes = data.metrics.redeem_success_count?.values?.count || 0;
  const invariant = successes === 1;
  if (!invariant) {
    console.error(`DOUBLE-SPEND INVARIANT FAILED: expected 1 success, got ${successes}`);
  } else {
    console.log('DOUBLE-SPEND INVARIANT PASS: exactly 1 redemption succeeded');
  }
  return {
    stdout: JSON.stringify({
      invariant_pass: invariant,
      redeem_success_count: successes,
      p95_ms: data.metrics.http_req_duration?.values?.['p(95)'] ?? null,
      http_failure_rate: data.metrics.http_req_failed?.values?.rate ?? null,
    }, null, 2) + '\n',
  };
}
