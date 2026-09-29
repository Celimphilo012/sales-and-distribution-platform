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
    // Shown in email subjects, SMS texts and the authenticator app's account name.
    appName: process.env.APP_NAME ?? 'Ordering System',
    // Where people open the ordering app (e.g. https://orders.example.com). Emails link to it
    // ("Review order"); left empty, emails simply carry no button.
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
    // Fallback delivery settings — an administrator normally sets these in the app instead.
    email: {
      // smtp = really send; log = print to the server log (the default until SMTP is configured).
      transport: process.env.EMAIL_TRANSPORT ?? (process.env.SMTP_HOST ? 'smtp' : 'log'),
      host: process.env.SMTP_HOST,
      port: int('SMTP_PORT', 587),
      secure: (process.env.SMTP_SECURE ?? 'false') === 'true', // true for port 465
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
      from: process.env.EMAIL_FROM ?? process.env.SMTP_USER ?? 'orders@localhost',
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
