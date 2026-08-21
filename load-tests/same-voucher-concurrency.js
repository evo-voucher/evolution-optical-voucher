import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const successCount = new Counter('redeem_success_count');
const unexpectedResponses = new Rate('unexpected_responses');

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
    unexpected_responses: ['rate<0.01'],
    redeem_success_count: ['count==1'],
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

  const controlled = res.status === 200 && body && typeof body.success === 'boolean';
  unexpectedResponses.add(!controlled);

  const isSuccess = controlled && body.success === true;
  if (isSuccess) successCount.add(1);

  check(res, {
    'response is controlled': () => controlled,
  });
}

export function handleSummary(data) {
  const successes = data.metrics.redeem_success_count?.values?.count || 0;
  const invariant = successes === 1;
  return {
    stdout: JSON.stringify({
      invariant_pass: invariant,
      redeem_success_count: successes,
      expected_rejections: 9,
      p95_ms: data.metrics.http_req_duration?.values?.['p(95)'] ?? null,
      http_failure_rate: data.metrics.http_req_failed?.values?.rate ?? null,
    }, null, 2) + '\n',
  };
}
