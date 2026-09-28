'use strict';

/**
 * Read-side parity check: replays the same requests against the legacy NestJS /backend and this
 * port (same distribution_platform database, same warehouse) and diffs status + body.
 *
 *   OLD_URL=http://localhost:3000 NEW_URL=http://localhost:3300 \
 *   PARITY_EMAIL=... PARITY_PASSWORD=... node test/parity.js
 *
 * Read-only: it never writes (apart from each server's own LOGIN audit row). Volatile fields
 * (timestamps, tokens) are normalised away.
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const OLD = process.env.OLD_URL ?? 'http://localhost:3000';
const NEW = process.env.NEW_URL ?? 'http://localhost:3300';
const EMAIL = process.env.PARITY_EMAIL ?? process.env.SEED_ADMIN_EMAIL;
const PASSWORD = process.env.PARITY_PASSWORD ?? process.env.SEED_ADMIN_PASSWORD;
const VOLATILE = new Set(['timestamp', 'accessToken', 'refreshToken']);

function normalise(value) {
  if (Array.isArray(value)) return value.map(normalise);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) if (!VOLATILE.has(key)) out[key] = normalise(value[key]);
    return out;
  }
  return value;
}

async function call(base, method, path, { token, body } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

function firstDiff(a, b, path = '$') {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') return `${path}: ${JSON.stringify(a)?.slice(0, 120)} != ${JSON.stringify(b)?.slice(0, 120)}`;
  if (Array.isArray(a) && a.length !== b.length) return `${path}: length ${a.length} != ${b.length}`;
  for (const key of new Set([...Object.keys(a), ...Object.keys(b)])) {
    const d = firstDiff(a[key], b[key], `${path}.${key}`);
    if (d) return d;
  }
  return null;
}

async function main() {
  const login = async (base) => (await call(base, 'POST', '/auth/login', { body: { email: EMAIL, password: PASSWORD } })).json.accessToken;
  const tokens = { old: await login(OLD), new: await login(NEW) };
  let same = 0;
  let total = 0;

  async function both(label, method, path, opts = {}) {
    total++;
    const [a, b] = await Promise.all([
      call(OLD, method, path, { ...opts, token: opts.auth === false ? undefined : tokens.old }),
      call(NEW, method, path, { ...opts, token: opts.auth === false ? undefined : tokens.new }),
    ]);
    const diff = a.status !== b.status ? `status ${a.status} != ${b.status}` : firstDiff(normalise(a.json), normalise(b.json));
    if (diff) console.log(`  DIFF  ${label}  -> ${diff}`);
    else {
      same++;
      console.log(`  ok    ${label}  [${a.status}]`);
    }
    return b.json;
  }
  const get = (path) => both(`GET ${path}`, 'GET', path);

  console.log('== reads ==');
  await get('/auth/me');
  await get('/users/me');
  const users = await get('/users');
  const roles = await get('/roles');
  await get('/permissions');
  await get('/audit-logs?pageSize=5');
  await get('/audit-logs?entity=orders&pageSize=5');
  const customers = await get('/customers');
  await get('/customers?includeInactive=true');
  await get('/customers?search=a');
  const orders = await get('/orders');
  await get('/orders?status=DRAFT');
  await get('/reports/orders');
  await get('/reports/orders?status=COMPLETED');
  await get('/dashboard');
  await get('/catalogue');
  await get('/catalogue?search=a');
  await get('/warehouse-locations');

  console.log('== by id ==');
  if (users[0]) await get(`/users/${users[0].id}`);
  if (roles[0]) await get(`/roles/${roles[0].id}`);
  if (customers[0]) await get(`/customers/${customers[0].id}`);
  for (const order of orders.slice(0, 5)) await get(`/orders/${order.id}`);
  if (customers[0]) await get(`/orders?customerId=${customers[0].id}`);

  console.log('== error shapes ==');
  await both('401 no token', 'GET', '/orders', { auth: false });
  await both('404 unknown route', 'GET', '/nope');
  await both('400 non-uuid id', 'GET', '/orders/not-a-uuid');
  await both('404 unknown order', 'GET', '/orders/00000000-0000-4000-8000-000000000000');
  await both('401 bad login', 'POST', '/auth/login', { auth: false, body: { email: 'nobody@example.com', password: 'x' } });
  await both('400 bad status filter', 'GET', '/orders?status=NOPE');

  console.log(`\n${same}/${total} identical`);
  if (same !== total) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
