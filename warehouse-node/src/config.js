'use strict';

require('dotenv').config();

function int(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error(`Env ${name} must be a number (got "${raw}")`);
  return value;
}

function list(name, fallback) {
  return (process.env[name] ?? fallback)
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);
}

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var ${name}`);
  return value;
}

function loadConfig() {
  return {
    port: int('PORT', 3100),
    // Set when the app is mounted under a sub-path (cPanel/Passenger passes the
    // FULL path through). Empty locally.
    basePath: (process.env.API_BASE_PATH ?? '').trim().replace(/^\/+|\/+$/g, ''),
    corsOrigins: list('CORS_ORIGINS', 'http://localhost:5173,http://localhost:8080,http://localhost:3001'),
    jwt: {
      accessSecret: required('JWT_ACCESS_SECRET'),
      accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN ?? '15m',
      refreshSecret: required('JWT_REFRESH_SECRET'),
      refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN ?? '7d',
    },
    cache: {
      store: process.env.CACHE_STORE ?? 'memory',
      enabled: (process.env.CACHE_ENABLED ?? 'true') !== 'false',
      maxEntries: int('CACHE_MAX_ENTRIES', 2000),
      // Permission sets are cached per user. Invalidated eagerly on any role/user
      // write in this process; the TTL bounds staleness across processes.
      permissionsTtlMs: int('CACHE_PERMISSIONS_TTL_MS', 30_000),
      apiKeyTtlMs: int('CACHE_API_KEY_TTL_MS', 60_000),
      referenceTtlMs: int('CACHE_REFERENCE_TTL_MS', 60_000),
      catalogueTtlMs: int('CACHE_CATALOGUE_TTL_MS', 60_000),
      reportsTtlMs: int('CACHE_REPORTS_TTL_MS', 30_000),
    },
    trustProxy: (process.env.TRUST_PROXY ?? 'true') !== 'false',
  };
}

module.exports = { loadConfig };
