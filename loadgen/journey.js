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

const PASS = __ENV.PASS || 'Training@123';
const PAGES = ['/dashboard', '/cards', '/loans', '/transactions', '/pay'];
// Payments RECIRCULATE within a pool of well-funded internal customers: each iteration picks one
// as the logged-in payer and ANOTHER as the payee, so money only moves between them and no single
// account drains. Why this matters: the old loadgen always paid FROM the one account
// cust00000001@bankobs TO external demo payees, so that account's balance fell to ~0 and every
// later debit returned ERR_INSUFFICIENT_FUNDS → account-service 409 → web-portal 502 — a steady,
// growing error rate on the RED dashboard that was pure data-drain, not a real fault. Each
// {cust,vpa} below is seeded in Oracle + vpa_registry (02-seed.cql) and funded with ₹200k+;
// cust00000001 is deliberately NOT a payer (its demo balance is already spent). The sender must be
// the logged-in customer, so payer identity and from_vpa are chosen together. Override the roster
// with POOL_CUSTS / POOL_VPAS (comma-separated, index-aligned).
const POOL_CUSTS = (__ENV.POOL_CUSTS || 'CUST-00000002,CUST-00000003,CUST-00000004,CUST-00000005').split(',');
const POOL_VPAS  = (__ENV.POOL_VPAS  || 'cust00000002@bankobs,cust00000003@bankobs,cust00000004@bankobs,cust00000005@bankobs').split(',');
const POOL = POOL_CUSTS.map((c, i) => ({ cust: c.trim(), vpa: POOL_VPAS[i].trim() }));

function pick(a) { return a[Math.floor(Math.random() * a.length)]; }

export default function () {
  // Act as a random pool customer this iteration — rotating the payer is what keeps any one
  // account from draining (the sender must be whoever is logged in).
  const me = pick(POOL);
  // 1) login — k6 keeps the bankobs_session cookie in the per-VU jar
  const login = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ customer_id: me.cust, password: PASS }),
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
    // Pay another pool member (never yourself) so funds recirculate and balances stay healthy.
    let payee = pick(POOL);
    if (POOL.length > 1) { while (payee.vpa === me.vpa) payee = pick(POOL); }
    const pay = http.post(
      `${BASE}/api/upi/pay`,
      JSON.stringify({ from_vpa: me.vpa, to_vpa: payee.vpa, amount: amt }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'upi_pay' }, timeout: '15s' },
    );
    check(pay, { 'pay 200': (r) => r.status === 200 }) || journeyErrors.add(1);
  }
  sleep(Math.random() * 0.8 + 0.2);
}
