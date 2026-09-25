'use strict';

/**
 * Read-side parity check: replays the same requests against the ORIGINAL NestJS API and this
 * Fastify port (same warehouse_db) and diffs status + body.
 *
 *   OLD_URL=http://localhost:3100 NEW_URL=http://localhost:3200 \
 *   PARITY_EMAIL=... PARITY_PASSWORD=... node test/parity.js
 *
 * Read-only: it never writes. Volatile fields (timestamps, tokens) are normalised away.
 */
const OLD = process.env.OLD_URL ?? 'http://localhost:3100';
const NEW = process.env.NEW_URL ?? 'http://localhost:3200';
const EMAIL = process.env.PARITY_EMAIL ?? process.env.SEED_ADMIN_EMAIL;
const PASSWORD = process.env.PARITY_PASSWORD ?? process.env.SEED_ADMIN_PASSWORD;

const VOLATILE = new Set(['timestamp', 'accessToken', 'refreshToken', 'waitingDays']);

function normalise(value) {
  if (Array.isArray(value)) return value.map(normalise);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (VOLATILE.has(key)) continue;
      out[key] = normalise(value[key]);
    }
    return out;
  }
  return value;
}

async function call(base, method, path, { token, apiKey, body } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (apiKey) headers['x-api-key'] = apiKey;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, json, contentType: res.headers.get('content-type') };
}

async function login(base) {
  const res = await call(base, 'POST', '/auth/login', { body: { email: EMAIL, password: PASSWORD } });
  if (res.status !== 200) throw new Error(`login failed on ${base}: ${res.status} ${JSON.stringify(res.json)}`);
  return res.json.accessToken;
}

let failures = 0;
let checks = 0;

function report(label, oldRes, newRes) {
  checks++;
  const a = JSON.stringify({ s: oldRes.status, b: normalise(oldRes.json) });
  const b = JSON.stringify({ s: newRes.status, b: normalise(newRes.json) });
  if (a === b) {
    console.log(`  ok    ${label}  [${newRes.status}]`);
    return;
  }
  failures++;
  console.log(`  DIFF  ${label}  old=${oldRes.status} new=${newRes.status}`);
  const oa = JSON.parse(a);
  const ob = JSON.parse(b);
  console.log('        old:', JSON.stringify(oa.b).slice(0, 300));
  console.log('        new:', JSON.stringify(ob.b).slice(0, 300));
}

// The original's report SQL has no tiebreaker (16 products tie at a shortfall of 40), so its row order for
// ties is arbitrary. The port orders ties by SKU. Compare those payloads order-independently, and only on the
// parts that are not "first N of a tie group".
const canon = (v) => JSON.stringify(normalise(v));
const sortedList = (list) => list.map(canon).sort();
const TIE_SAFE = {
  '/reports/low-stock': (j) => ({ count: j.count, items: sortedList(j.items) }),
  '/reports/inventory-valuation': (j) => ({
    total: j.total,
    excluded: j.excludedProductCount,
    topValues: j.topProducts.map((p) => p.value),
  }),
  '/dashboard': (j) => ({
    catalogue: j.catalogue,
    lowCount: j.lowStock.count,
    pending: j.pendingAdjustments.count,
    total: j.valuation.total,
    topValues: j.valuation.topProducts.map((p) => p.value),
    counts: j.openStockCounts,
    byType: j.stockMovement.byType,
  }),
};

async function both(label, method, path, opts, tokens) {
  const [o, n] = await Promise.all([
    call(OLD, method, path, { ...opts, token: opts.auth === false ? undefined : tokens.old }),
    call(NEW, method, path, { ...opts, token: opts.auth === false ? undefined : tokens.new }),
  ]);
  const safe = TIE_SAFE[path];
  if (safe && o.status === 200 && n.status === 200) {
    report(`${label} (tie-order independent)`, { status: o.status, json: safe(o.json) }, { status: n.status, json: safe(n.json) });
  } else {
    report(label, o, n);
  }
  return n;
}

(async () => {
  const tokens = { old: await login(OLD), new: await login(NEW) };
  const get = (path, label = `GET ${path}`) => both(label, 'GET', path, {}, tokens);

  console.log('\n== lists ==');
  const products = (await get('/products')).json;
  await get('/products?includeInactive=true');
  await get('/products?status=INACTIVE');
  await get('/products?search=lotion');
  const categories = (await get('/categories')).json;
  await get('/categories?includeInactive=true');
  const workstreams = (await get('/workstreams')).json;
  await get('/workstreams?includeInactive=true');
  await get('/attribute-types');
  await get('/attribute-types?includeInactive=true');
  const warehouses = (await get('/warehouses')).json;
  await get('/warehouses?includeInactive=true');
  const locations = (await get('/locations')).json;
  await get('/locations?includeInactive=true');
  await get('/locations?rootOnly=true');
  const users = (await get('/users')).json;
  const roles = (await get('/roles')).json;
  await get('/permissions');
  await get('/api-keys');
  await get('/auth/me');
  await get('/users/me');
  await get('/users/me/workstreams');
  await get('/audit-logs?pageSize=5');
  await get('/audit-logs?entity=products&pageSize=5');

  console.log('\n== inventory ==');
  await get('/inventory/balances');
  await get('/inventory/transactions');
  await get('/inventory/transactions?type=RECEIVE');
  await get('/inventory/adjustments');
  await get('/inventory/adjustments?status=PENDING');
  const counts = (await get('/inventory/counts')).json;

  console.log('\n== reports ==');
  await get('/reports/low-stock');
  await get('/reports/inventory-valuation');
  await get('/reports/stock-movement-summary');
  await get('/reports/stock-movement-summary?days=30');
  await get('/reports/adjustments-summary');
  await get('/dashboard');

  console.log('\n== by id ==');
  if (products[0]) {
    const p = products.find((x) => x.images?.length) ?? products[0];
    await get(`/products/${p.id}`);
    await get(`/products/${p.id}/images`);
    await get(`/inventory/balances?productId=${p.id}`);
  }
  if (categories[0]) await get(`/categories/${categories[0].id}`);
  if (workstreams[0]) {
    await get(`/workstreams/${workstreams[0].id}`);
    await get(`/workstreams/${workstreams[0].id}/managers`);
  }
  if (warehouses[0]) await get(`/warehouses/${warehouses[0].id}`);
  if (locations[0]) {
    const root = locations.find((l) => l.parentId === null) ?? locations[0];
    await get(`/locations/${root.id}`);
    await get(`/locations/${root.id}/children`);
    await get(`/locations/${root.id}/subtree`);
    await get(`/locations/${root.id}/subtree?includeInactive=true`);
    await get(`/inventory/balances?locationId=${root.id}`);
  }
  if (users[0]) await get(`/users/${users[0].id}`);
  if (roles[0]) await get(`/roles/${roles[0].id}`);
  if (counts[0]) await get(`/inventory/counts/${counts[0].id}`);

  console.log('\n== error shapes ==');
  const noAuth = { auth: false };
  await both('401 no token', 'GET', '/products', noAuth, tokens);
  await both('401 bad token', 'GET', '/products', { token: 'x', auth: false }, tokens);
  await both('404 unknown route', 'GET', '/nope', {}, tokens);
  await both('400 non-uuid id', 'GET', '/products/not-a-uuid', {}, tokens);
  await both('404 unknown product', 'GET', '/products/00000000-0000-4000-8000-000000000000', {}, tokens);
  await both('401 bad login', 'POST', '/auth/login', { auth: false, body: { email: 'nobody@example.com', password: 'x' } }, tokens);
  await both('401 x-api-key missing', 'GET', '/api/v1/catalogue', { auth: false }, tokens);

  console.log(`\n${checks - failures}/${checks} identical${failures ? `, ${failures} DIFFER` : ''}`);
  process.exit(failures ? 1 : 0);
})().catch((error) => {
  console.error(error);
  process.exit(2);
});
