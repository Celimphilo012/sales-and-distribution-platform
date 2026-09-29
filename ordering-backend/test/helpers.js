'use strict';

/**
 * Integration-test harness: the real Express app on a random localhost port, against a THROWAWAY
 * database (refuses any name not ending in `_test`), talking to a FAKE warehouse (see
 * createFakeWarehouse) — so no test ever touches real stock.
 *
 * One-time setup:
 *   mysql -u root -e "CREATE DATABASE distribution_platform_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
 *   mysql -u root distribution_platform_test < db/schema.sql
 *   DATABASE_URL=mysql://root:@localhost:3306/distribution_platform_test SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD=TestPass123! npm run seed
 */
const http = require('http');
const express = require('express');

const TEST_URL = process.env.TEST_DATABASE_URL ?? 'mysql://root:@localhost:3306/distribution_platform_test';
if (!/_test(\?|$)/.test(TEST_URL)) throw new Error(`Refusing to run tests against "${TEST_URL}" — the database name must end in _test`);

process.env.DATABASE_URL = TEST_URL;
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.LOG_LEVEL = 'silent';

const { loadConfig } = require('../src/config');
const { buildApp } = require('../src/app');

const ADMIN = { email: 'admin@test.local', password: 'TestPass123!' };

const listen = (handler) =>
  new Promise((resolve) => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });

/**
 * A stand-in for the warehouse's external API: a two-product catalogue, two warehouses of leaf
 * locations (stock tracked per product + location, each with a stock age for FIFO), and real
 * reserve/release/issue bookkeeping (idempotent on reference, shortfall as HTTP 200 success:false) —
 * the contract the ordering system relies on. `calls` records every request. Soap starts with 100 at
 * `locationId` (warehouse W1); tests put stock elsewhere with `state.setStock(productId, locationId, qty, age)`.
 */
async function createFakeWarehouse() {
  const SOAP = '11111111-1111-4111-8111-111111111111';
  const locations = [
    { id: '33333333-3333-4333-8333-333333333333', warehouseId: 'w1', name: 'Bin', parentId: null },
    { id: '44444444-4444-4444-8444-444444444444', warehouseId: 'w1', name: 'Shelf B', parentId: null },
    { id: '55555555-5555-4555-8555-555555555555', warehouseId: 'w1', name: 'Shelf C', parentId: null },
    { id: '66666666-6666-4666-8666-666666666666', warehouseId: 'w2', name: 'Far Bin', parentId: null },
  ];
  const state = {
    products: [
      { id: SOAP, sku: 'SOAP-1', name: 'Bar Soap', status: 'ACTIVE', sellingPrice: '12.5', category: { id: 'c', name: 'Soap' } },
      { id: '22222222-2222-4222-8222-222222222222', sku: 'OLD-1', name: 'Old Line', status: 'INACTIVE', sellingPrice: '9', category: { id: 'c', name: 'Soap' } },
    ],
    locationId: locations[0].id,
    locations,
    stock: new Map(), // productId:locationId -> { available, oldestStockAt }
    reservations: new Map(),
    calls: [],
    down: false,
    setStock(productId, locationId, available, oldestStockAt = '2026-01-01T00:00:00.000Z') {
      state.stock.set(`${productId}:${locationId}`, { available, oldestStockAt });
    },
    availableAt: (productId, locationId) => state.stock.get(`${productId}:${locationId}`)?.available ?? 0,
    adjust(productId, locationId, delta) {
      const entry = state.stock.get(`${productId}:${locationId}`) ?? { available: 0, oldestStockAt: null };
      entry.available += delta;
      state.stock.set(`${productId}:${locationId}`, entry);
    },
  };
  state.setStock(SOAP, state.locationId, 100);

  const app = express();
  app.use(express.json());
  app.use((req, res, next) => {
    state.calls.push({ method: req.method, path: req.path, body: req.body, key: req.headers['x-api-key'] });
    if (state.down) return res.destroy();
    next();
  });
  app.get('/api/v1/catalogue', (req, res) => {
    const products = state.products.filter((p) => req.query.includeInactive === 'true' || p.status === (req.query.status ?? 'ACTIVE'));
    res.json({ categories: [], products });
  });
  app.get('/api/v1/locations', (req, res) =>
    res.json({
      warehouses: [
        { id: 'w1', name: 'Main WH', code: 'W1', isActive: true },
        { id: 'w2', name: 'Far WH', code: 'W2', isActive: true },
      ],
      locations: state.locations,
    }),
  );
  app.post('/api/v1/stock/allocation-options', (req, res) => {
    res.json({
      products: req.body.productIds.map((productId) => ({
        productId,
        locations: state.locations
          .map((l) => ({ l, entry: state.stock.get(`${productId}:${l.id}`) }))
          .filter(({ entry }) => entry && entry.available > 0)
          .map(({ l, entry }) => ({ locationId: l.id, warehouseId: l.warehouseId, available: entry.available, oldestStockAt: entry.oldestStockAt })),
      })),
    });
  });
  app.post('/api/v1/stock/reserve', (req, res) => {
    const { reference, lines, label } = req.body;
    if (state.reservations.has(reference)) return res.json({ success: true, reference, status: 'RESERVED', reserved: lines });
    const shortLines = lines
      .filter((l) => state.availableAt(l.productId, l.locationId) < l.quantity)
      .map((l) => ({ productId: l.productId, locationId: l.locationId, requested: l.quantity, available: state.availableAt(l.productId, l.locationId) }));
    if (shortLines.length) return res.json({ success: false, reference, shortLines });
    for (const l of lines) state.adjust(l.productId, l.locationId, -l.quantity);
    state.reservations.set(reference, { lines, label, status: 'RESERVED' });
    res.json({ success: true, reference, status: 'RESERVED', reserved: lines });
  });
  app.post('/api/v1/stock/release', (req, res) => {
    const r = state.reservations.get(req.body.reference);
    if (r && r.status === 'RESERVED') {
      for (const l of r.lines) state.adjust(l.productId, l.locationId, l.quantity);
      r.status = 'RELEASED';
    }
    res.json({ success: true, reference: req.body.reference, alreadyReleased: false, released: [] });
  });
  app.post('/api/v1/stock/issue', (req, res) => {
    const r = state.reservations.get(req.body.reference);
    const issued = r.lines.map((l) => {
      const line = req.body.lines.find((x) => x.productId === l.productId && x.locationId === l.locationId);
      const qty = line?.quantity ?? 0;
      state.adjust(l.productId, l.locationId, l.quantity - qty); // release all, issue qty (on hand leaves)
      return { productId: l.productId, locationId: l.locationId, reserved: l.quantity, issued: qty };
    });
    r.status = 'ISSUED';
    res.json({ success: true, reference: req.body.reference, alreadyIssued: false, issued });
  });
  const server = await listen(app);
  return { state, url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) };
}

/**
 * Email and SMS always go to the in-memory `outbox`. One-time-code confirmation is OFF unless a
 * suite asks for it with { otp: { enabled: true } } — suites that are not about OTP stay readable.
 */
async function createTestApp(configOverrides = {}) {
  const base = loadConfig();
  const config = {
    ...base,
    ...configOverrides,
    warehouseApi: { ...base.warehouseApi, ...(configOverrides.warehouseApi ?? {}) },
    otp: { ...base.otp, enabled: false, ...(configOverrides.otp ?? {}) },
    email: { ...base.email, transport: 'memory' },
    sms: { ...base.sms, transport: 'memory' },
  };
  const app = buildApp({ config });
  const server = await listen(app);
  const origin = `http://127.0.0.1:${server.address().port}`;
  return {
    origin,
    db: app.locals.db,
    outbox: app.locals.services.notifier.outbox,
    close: async () => {
      await new Promise((r) => server.close(r));
      await app.close();
    },
  };
}

/** Tiny JSON client: c.get/post/patch/delete(path, body?, headers?) -> { status, json }. */
function client(origin, token) {
  const request = async (method, path, body, extraHeaders = {}) => {
    const headers = { ...(token ? { authorization: `Bearer ${token}` } : {}), ...extraHeaders };
    if (body !== undefined) headers['content-type'] = 'application/json';
    const res = await fetch(origin + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      json = undefined;
    }
    return { status: res.status, json, body: text };
  };
  return {
    get: (p, h) => request('GET', p, undefined, h),
    post: (p, b, h) => request('POST', p, b ?? {}, h),
    patch: (p, b, h) => request('PATCH', p, b, h),
    put: (p, b, h) => request('PUT', p, b, h),
    delete: (p, h) => request('DELETE', p, undefined, h),
  };
}

async function loginAs(origin, credentials = ADMIN) {
  const res = await client(origin).post('/auth/login', credentials);
  if (res.status !== 200) throw new Error(`login failed for ${credentials.email}: ${res.status} ${res.body}`);
  return res.json;
}

const uid = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
const settle = (ms = 150) => new Promise((r) => setTimeout(r, ms));

module.exports = { createFakeWarehouse, createTestApp, client, loginAs, uid, settle, ADMIN };
