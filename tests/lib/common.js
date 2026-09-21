import { check } from 'k6';

export const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function authHeaders(token) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
}

export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Ramp-up profile that lets us find the breaking point:
// 10% -> 50% -> 100% (twice) -> 0
// Durations are overridable for quick smoke runs:
//   LOAD_RAMP=5s LOAD_HOLD=10s LOAD_DOWN=2s
export function rampStages(peakRps) {
  const p = Math.max(1, Math.round(peakRps));
  const ramp = __ENV.LOAD_RAMP || '1m';
  const hold = __ENV.LOAD_HOLD || '2m';
  const down = __ENV.LOAD_DOWN || '30s';
  return [
    { target: Math.max(1, Math.round(p * 0.1)), duration: ramp },
    { target: Math.max(1, Math.round(p * 0.5)), duration: ramp },
    { target: p, duration: hold },
    { target: p, duration: hold },
    { target: 0, duration: down },
  ];
}

// One scenario per endpoint, each driven by a ramping arrival-rate executor.
export function arrivalScenario(exec, peakRps, tags = {}) {
  const rate = Math.max(1, Math.round(peakRps));
  return {
    executor: 'ramping-arrival-rate',
    exec,
    startRate: Math.max(1, Math.round(rate * 0.1)),
    timeUnit: '1s',
    preAllocatedVUs: Math.max(10, Math.ceil(rate * 0.5)),
    maxVUs: Math.max(50, rate * 4),
    stages: rampStages(rate),
    tags,
  };
}

export function ok(res, name, expected = 200) {
  return check(res, {
    [`${name}: status ${expected}`]: (r) => r.status === expected,
  });
}

export function baseThresholds(extra = {}) {
  return Object.assign(
    {
      http_req_failed: ['rate<0.05'],
      'http_req_duration{expected_response:true}': ['p(95)<800', 'p(99)<2000'],
      checks: ['rate>0.95'],
    },
    extra
  );
}