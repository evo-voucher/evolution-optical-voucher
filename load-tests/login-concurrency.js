import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const loginErrors = new Rate('login_errors');
const loginDuration = new Trend('login_duration', true);

const baseUrl = __ENV.SUPABASE_URL;
const anonKey = __ENV.SUPABASE_ANON_KEY;
const email = __ENV.TEST_LOGIN_EMAIL;
const password = __ENV.TEST_LOGIN_PASSWORD;
const targetEnv = (__ENV.TARGET_ENV || '').toLowerCase();
const stage = (__ENV.LOGIN_STAGE || '10').trim();

if (!['test', 'development'].includes(targetEnv)) {
  throw new Error('Login load test blocked. TARGET_ENV must be test or development.');
}
if (!baseUrl || !anonKey || !email || !password) {
  throw new Error('SUPABASE_URL, SUPABASE_ANON_KEY, TEST_LOGIN_EMAIL and TEST_LOGIN_PASSWORD are required.');
}
if (!['10', '25', '50'].includes(stage)) {
  throw new Error('LOGIN_STAGE must be one of: 10, 25, 50.');
}

const vus = Number(stage);

export const options = {
  scenarios: {
    concurrent_login: {
      executor: 'shared-iterations',
      vus,
      iterations: vus,
      maxDuration: '30s',
    },
  },
  thresholds: {
    login_errors: ['rate<0.01'],
    login_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const url = `${baseUrl}/auth/v1/token?grant_type=password`;
  const payload = JSON.stringify({ email, password });

  const res = http.post(url, payload, {
    headers: {
      apikey: anonKey,
      'Content-Type': 'application/json',
    },
  });

  loginDuration.add(res.timings.duration);

  let body = null;
  try { body = res.json(); } catch (_) {}

  const ok = res.status === 200 && body && body.access_token && body.refresh_token && body.user && body.user.id;
  loginErrors.add(!ok);

  check(res, {
    'login returns 200': (r) => r.status === 200,
    'access token returned': () => !!body?.access_token,
    'refresh token returned': () => !!body?.refresh_token,
    'user id returned': () => !!body?.user?.id,
  });
}

export function handleSummary(data) {
  const p95 = data.metrics.login_duration?.values?.['p(95)'] ?? null;
  const errorRate = data.metrics.login_errors?.values?.rate ?? null;
  const httpFail = data.metrics.http_req_failed?.values?.rate ?? null;
  const pass = errorRate !== null && errorRate < 0.01 && p95 !== null && p95 < 3000 && httpFail !== null && httpFail < 0.01;

  return {
    stdout: JSON.stringify({
      test: 'concurrent_login',
      stage: vus,
      acceptance_pass: pass,
      p95_ms: p95,
      login_error_rate: errorRate,
      http_failure_rate: httpFail,
      environment: targetEnv,
    }, null, 2) + '\n',
  };
}
