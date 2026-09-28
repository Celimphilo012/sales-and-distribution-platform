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
 * A stand-in for the warehouse's external API: a two-product catalogue, one leaf location, and
 * real reserve/release/issue bookkeeping (idempotent on reference, shortfall as HTTP 200
 * success:false) — the contract the ordering system relies on. `calls` records every request.
 */
async function createFakeWarehouse() {
  const state = {
    products: [
      { id: '11111111-1111-4111-8111-111111111111', sku: 'SOAP-1', name: 'Bar Soap', status: 'ACTIVE', sellingPrice: '12.5', category: { id: 'c', name: 'Soap' } },
      { id: '22222222-2222-4222-8222-222222222222', sku: 'OLD-1', name: 'Old Line', status: 'INACTIVE', sellingPrice: '9', category: { id: 'c', name: 'Soap' } },
    ],
    locationId: '33333333-3333-4333-8333-333333333333',
    available: new Map([['11111111-1111-4111-8111-111111111111', 100]]),
    reservations: new Map(),
    calls: [],
    down: false,
  };
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
    res.json({ warehouses: [{ id: 'w', name: 'WH', code: 'WH', isActive: true }], locations: [{ id: state.locationId, name: 'Bin', parentId: null }] }),
  );
  app.post('/api/v1/stock/reserve', (req, res) => {
    const { reference, lines, label } = req.body;
    if (state.reservations.has(reference)) return res.json({ success: true, reference, status: 'RESERVED', reserved: lines });
    const shortLines = lines
      .filter((l) => (state.available.get(l.productId) ?? 0) < l.quantity)
      .map((l) => ({ productId: l.productId, locationId: l.locationId, requested: l.quantity, available: state.available.get(l.productId) ?? 0 }));
    if (shortLines.length) return res.json({ success: false, reference, shortLines });
    for (const l of lines) state.available.set(l.productId, state.available.get(l.productId) - l.quantity);
    state.reservations.set(reference, { lines, label, status: 'RESERVED' });
    res.json({ success: true, reference, status: 'RESERVED', reserved: lines });
  });
  app.post('/api/v1/stock/release', (req, res) => {
    const r = state.reservations.get(req.body.reference);
    if (r && r.status === 'RESERVED') {
      for (const l of r.lines) state.available.set(l.productId, state.available.get(l.productId) + l.quantity);
      r.status = 'RELEASED';
    }
    res.json({ success: true, reference: req.body.reference, alreadyReleased: false, released: [] });
  });
  app.post('/api/v1/stock/issue', (req, res) => {
    const r = state.reservations.get(req.body.reference);
    const issued = r.lines.map((l) => {
      const line = req.body.lines.find((x) => x.productId === l.productId && x.locationId === l.locationId);
      const qty = line?.quantity ?? 0;
      state.available.set(l.productId, state.available.get(l.productId) + l.quantity - qty); // release all, issue qty
      return { productId: l.productId, locationId: l.locationId, reserved: l.quantity, issued: qty };
    });
    r.status = 'ISSUED';
    res.json({ success: true, reference: req.body.reference, alreadyIssued: false, issued });
  });
  const server = await listen(app);
  return { state, url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(r)) };
}

async function createTestApp(configOverrides = {}) {
  const base = loadConfig();
  const config = { ...base, ...configOverrides, warehouseApi: { ...base.warehouseApi, ...(configOverrides.warehouseApi ?? {}) } };
  const app = buildApp({ config });
  const server = await listen(app);
  const origin = `http://127.0.0.1:${server.address().port}`;
  return {
    origin,
    db: app.locals.db,
    close: async () => {
      await new Promise((r) => server.close(r));
      await app.close();
    },
  };
}

/** Tiny JSON client: c.get/post/patch/delete(path, body?) -> { status, json }. */
function client(origin, token) {
  const request = async (method, path, body) => {
    const headers = token ? { authorization: `Bearer ${token}` } : {};
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
    get: (p) => request('GET', p),
    post: (p, b) => request('POST', p, b ?? {}),
    patch: (p, b) => request('PATCH', p, b),
    put: (p, b) => request('PUT', p, b),
    delete: (p) => request('DELETE', p),
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
