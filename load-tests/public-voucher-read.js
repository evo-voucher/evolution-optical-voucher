import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errors = new Rate('business_errors');
const latency = new Trend('public_voucher_latency', true);

const baseUrl = __ENV.SUPABASE_URL;
const anonKey = __ENV.SUPABASE_ANON_KEY;
const publicToken = __ENV.PUBLIC_TOKEN;

if (!baseUrl || !anonKey || !publicToken) {
  throw new Error('SUPABASE_URL, SUPABASE_ANON_KEY and PUBLIC_TOKEN are required');
}

export const options = {
  scenarios: {
    public_voucher_read: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '60s', target: 25 },
        { duration: '30s', target: 50 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
    business_errors: ['rate<0.01'],
  },
};

export default function () {
  const url = `${baseUrl}/rest/v1/rpc/get_public_voucher`;
  const payload = JSON.stringify({ p_token: publicToken });
  const res = http.post(url, payload, {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      'Content-Type': 'application/json',
    },
  });

  latency.add(res.timings.duration);
  let body;
  try { body = res.json(); } catch (_) { body = null; }
  const ok = check(res, {
    'HTTP 200': (r) => r.status === 200,
    'voucher RPC success': () => body && body.success === true,
  });
  errors.add(!ok);
}
