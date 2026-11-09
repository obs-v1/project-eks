// BankObs end-to-end customer journey — generates distributed traces across the fleet.
// Each VU: log in (auth path) → browse 2–4 server-rendered pages (each fans out to the
// account / card / loan / transaction / statement services) → sometimes attempt a UPI
// payment (payment-gateway → upi-service → router → fraud → ledger). All of it is OTel-
// traced, so Jaeger + the spanmetrics RED dashboards light up under this load.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://web-portal:8200';
const VUS = parseInt(__ENV.VUS || '10', 10);
const DURATION = __ENV.DURATION || '24h';
const PAY_PROB = parseFloat(__ENV.PAY_PROB || '0.3');

const journeyErrors = new Rate('journey_errors');

export const options = {
  scenarios: {
    customers: { executor: 'constant-vus', vus: VUS, duration: DURATION },
  },
  thresholds: { journey_errors: ['rate<0.9'] }, // informational; faults are expected
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,
};

const CUST = __ENV.CUST || 'CUST-00000001';
const PASS = __ENV.PASS || 'Training@123';
const PAGES = ['/dashboard', '/cards', '/loans', '/transactions', '/pay'];

function pick(a) { return a[Math.floor(Math.random() * a.length)]; }

export default function () {
  // 1) login — k6 keeps the bankobs_session cookie in the per-VU jar
  const login = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ customer_id: CUST, password: PASS }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'login' } },
  );
  const okLogin = check(login, { 'login 200': (r) => r.status === 200 });
  journeyErrors.add(!okLogin);
  if (!okLogin) { sleep(1); return; }
  sleep(Math.random() * 0.8 + 0.2);

  // 2) browse 2–4 authenticated pages (server-rendered → backend services → traces)
  const hops = 2 + Math.floor(Math.random() * 3);
  for (let i = 0; i < hops; i++) {
    const p = pick(PAGES);
    const r = http.get(`${BASE}${p}`, { tags: { name: `page:${p}` } });
    check(r, { 'page 200': (x) => x.status === 200 }) || journeyErrors.add(1);
    sleep(Math.random() * 1.2 + 0.2);
  }

  // 3) sometimes send a UPI payment (full payment chain; best-effort — may fail under a fault)
  if (Math.random() < PAY_PROB) {
    const amt = Math.floor(Math.random() * 500) + 10;
    http.post(
      `${BASE}/api/upi/pay`,
      JSON.stringify({ from_vpa: 'user1@ybl', to_vpa: pick(['store@paytm', 'merchant@okaxis', 'shop@okhdfcbank']), amount: amt }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'upi_pay' }, timeout: '15s' },
    );
  }
  sleep(Math.random() * 0.8 + 0.2);
}
