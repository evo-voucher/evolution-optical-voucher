import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const businessErrors = new Rate('business_errors');

const baseUrl = __ENV.SUPABASE_URL;
const anonKey = __ENV.SUPABASE_ANON_KEY;
const publicToken = __ENV.PUBLIC_TOKEN;
const targetEnv = (__ENV.TARGET_ENV || '').toLowerCase();

if (!['test', 'development'].includes(targetEnv)) {
  throw new Error('Mixed peak load test blocked. TARGET_ENV must be test or development.');
}
if (!baseUrl || !anonKey || !publicToken) {
  throw new Error('SUPABASE_URL, SUPABASE_ANON_KEY and PUBLIC_TOKEN are required');
}

export const options = {
  scenarios: {
    customer_peak: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 150,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '60s', target: 50 },
        { duration: '30s', target: 100 },
        { duration: '30s', target: 10 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<2000'],
    business_errors: ['rate<0.02'],
  },
};

export default function () {
  const res = http.post(
    `${baseUrl}/rest/v1/rpc/get_public_voucher`,
    JSON.stringify({ p_token: publicToken }),
    {
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        'Content-Type': 'application/json',
      },
    },
  );

  let body;
  try { body = res.json(); } catch (_) { body = null; }

  const ok = check(res, {
    'HTTP 200': (r) => r.status === 200,
    'public voucher success': () => body && body.success === true,
  });
  businessErrors.add(!ok);
}
