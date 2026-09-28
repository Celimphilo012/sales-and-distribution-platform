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
    port: int('PORT', 3200),
    databaseUrl: required('DATABASE_URL'),
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
    appName: process.env.APP_NAME ?? 'Warehouse System',
    // Where people open the warehouse app (e.g. https://warehouse.example.com). Emails link to it
    // ("Review adjustment"); left empty, emails simply carry no button.
    appUrl: (process.env.APP_URL ?? '').replace(/\/+$/, ''),
    // Encrypts secrets at rest: authenticator-app (TOTP) secrets and the SMTP password / httpSMS
    // key saved from the admin screen. Set it once and never change it: rotating it makes every
    // enrolled authenticator app and every saved delivery credential unreadable. Falls back to a
    // key derived from JWT_REFRESH_SECRET so local dev works without it.
    secretsKey: process.env.SECRETS_ENCRYPTION_KEY || `derived:${required('JWT_REFRESH_SECRET')}`,
    otp: {
      // Deliberately NOT read from the environment: step-up codes cannot be switched off in a
      // deployment. Only the test harness turns this off (for suites that are not about OTP).
      enabled: true,
      codeTtlMs: int('OTP_CODE_TTL_MS', 10 * 60_000),
      maxAttempts: 5,
      // At most this many codes may be requested per user per window (SMS costs money).
      maxPerWindow: int('OTP_MAX_PER_WINDOW', 5),
      windowMs: 10 * 60_000,
    },
    email: {
      // smtp = really send; log = print to the server log (the default until SMTP is configured).
      transport: process.env.EMAIL_TRANSPORT ?? (process.env.SMTP_HOST ? 'smtp' : 'log'),
      host: process.env.SMTP_HOST,
      port: int('SMTP_PORT', 587),
      secure: (process.env.SMTP_SECURE ?? 'false') === 'true', // true for port 465
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
      from: process.env.EMAIL_FROM ?? process.env.SMTP_USER ?? 'warehouse@localhost',
    },
    sms: {
      // httpsms = really send via httpsms.com; log = print to the server log (default until configured).
      transport: process.env.SMS_TRANSPORT ?? (process.env.HTTPSMS_API_KEY ? 'httpsms' : 'log'),
      apiKey: process.env.HTTPSMS_API_KEY,
      from: process.env.HTTPSMS_FROM, // the httpSMS-registered phone number, +country format
      baseUrl: process.env.HTTPSMS_BASE_URL ?? 'https://api.httpsms.com',
    },
  };
}

module.exports = { loadConfig };
