'use strict';

/**
 * Integration-test harness. Boots the real Fastify app (in-process, via inject) against a THROWAWAY
 * database. It refuses to run against anything whose name does not end in `_test`, so a mistyped env
 * var can never write ledger rows into a real warehouse_db.
 *
 * One-time setup:
 *   mysql -u root -e "CREATE DATABASE warehouse_db_test"
 *   DATABASE_URL=mysql://root:@localhost:3306/warehouse_db_test npx prisma migrate deploy
 *   DATABASE_URL=... SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD=TestPass123! node prisma/seed.js
 */
const TEST_URL = process.env.TEST_DATABASE_URL ?? 'mysql://root:@localhost:3306/warehouse_db_test';
if (!/_test(\?|$)/.test(TEST_URL)) {
  throw new Error(`Refusing to run tests against "${TEST_URL}" — the database name must end in _test`);
}

process.env.DATABASE_URL = TEST_URL;
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.JWT_ACCESS_EXPIRES_IN = '15m';
process.env.JWT_REFRESH_EXPIRES_IN = '7d';
process.env.LOG_LEVEL = 'silent';

const { loadConfig } = require('../src/config');
const { buildApp } = require('../src/app');

const ADMIN = {
  email: process.env.TEST_ADMIN_EMAIL ?? 'admin@test.local',
  password: process.env.TEST_ADMIN_PASSWORD ?? 'TestPass123!',
};

async function createTestApp(configOverrides = {}) {
  const base = loadConfig();
  const config = { ...base, ...configOverrides, cache: { ...base.cache, ...(configOverrides.cache ?? {}) } };
  const app = await buildApp({ config, logger: false });
  await app.ready();
  return app;
}

/** Small client around app.inject that carries an auth header and parses JSON. */
function client(app, defaults = {}) {
  async function request(method, url, { body, headers = {}, token, apiKey, raw } = {}) {
    const h = { ...defaults.headers, ...headers };
    const bearer = token ?? defaults.token;
    if (bearer) h.authorization = `Bearer ${bearer}`;
    if (apiKey) h['x-api-key'] = apiKey;
    const options = { method, url, headers: h };
    if (raw) {
      options.payload = raw.payload;
      h['content-type'] = raw.contentType;
    } else if (body !== undefined) {
      options.payload = body;
    }
    const res = await app.inject(options);
    let json;
    try {
      json = res.json();
    } catch {
      json = undefined;
    }
    return { status: res.statusCode, json, body: res.body, headers: res.headers, rawBuffer: res.rawPayload };
  }
  return {
    get: (url, opts) => request('GET', url, opts),
    post: (url, body, opts) => request('POST', url, { ...opts, body }),
    patch: (url, body, opts) => request('PATCH', url, { ...opts, body }),
    put: (url, body, opts) => request('PUT', url, { ...opts, body }),
    delete: (url, opts) => request('DELETE', url, opts),
    request,
  };
}

async function loginAs(app, credentials = ADMIN) {
  const res = await app.inject({ method: 'POST', url: '/auth/login', payload: credentials });
  if (res.statusCode !== 200) throw new Error(`login failed for ${credentials.email}: ${res.statusCode} ${res.body}`);
  return res.json();
}

/** Builds a multipart/form-data body with the platform's own FormData/Response (no extra dependency). */
async function multipart(fields = {}, files = []) {
  const form = new FormData();
  for (const [key, value] of Object.entries(fields)) form.append(key, String(value));
  for (const file of files) form.append(file.field, new Blob([file.content], { type: file.type }), file.filename);
  const response = new Response(form);
  return { payload: Buffer.from(await response.arrayBuffer()), contentType: response.headers.get('content-type') };
}

/** Unique suffix so re-runs never collide on unique columns (sku, code, email). */
const uid = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** Lets fire-and-forget work (audit rows written in onResponse) finish before asserting on it. */
const settle = (ms = 150) => new Promise((resolve) => setTimeout(resolve, ms));

module.exports = { createTestApp, client, loginAs, multipart, uid, settle, ADMIN };
