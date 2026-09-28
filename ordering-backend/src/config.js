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
    port: int('PORT', 3300),
    databaseUrl: required('DATABASE_URL'),
    // Set when the app is mounted under a sub-path (cPanel/Passenger passes the FULL path through).
    basePath: (process.env.API_BASE_PATH ?? '').trim().replace(/^\/+|\/+$/g, ''),
    corsOrigins: list('CORS_ORIGINS', 'http://localhost:5173,http://localhost:8080,http://localhost:3001'),
    jwt: {
      accessSecret: required('JWT_ACCESS_SECRET'),
      accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN ?? '15m',
      refreshSecret: required('JWT_REFRESH_SECRET'),
      refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN ?? '7d',
    },
    // This app is a CLIENT of the warehouse's API-key-protected external API (ARCHITECTURE.md §A2).
    warehouseApi: {
      url: process.env.WAREHOUSE_API_URL ?? 'http://localhost:3200',
      key: process.env.WAREHOUSE_API_KEY ?? '',
      timeoutMs: int('WAREHOUSE_API_TIMEOUT_MS', 20_000),
    },
    trustProxy: (process.env.TRUST_PROXY ?? 'true') !== 'false',
  };
}

module.exports = { loadConfig };
