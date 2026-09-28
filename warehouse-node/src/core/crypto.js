'use strict';

const crypto = require('crypto');

/**
 * Small, dependency-free crypto helpers for MFA and one-time codes (Node's built-in `crypto`).
 *
 *  - numeric codes for email/SMS, stored only as an HMAC (never in clear);
 *  - TOTP (RFC 6238 — what Google/Microsoft Authenticator, Authy, etc. implement): 30-second
 *    steps, 6 digits, HMAC-SHA1, base32 secrets, ±1 step tolerance for clock drift;
 *  - AES-256-GCM encryption for TOTP secrets at rest (they must be recoverable to verify codes,
 *    so they are encrypted rather than hashed).
 */

// ---- One-time numeric codes -----------------------------------------------------------------

/** A uniformly random 6-digit code (crypto.randomInt, not Math.random). */
const randomCode = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');

/** Keyed hash of a code, bound to its challenge id so a hash can't be replayed on another challenge. */
function hashCode(key, challengeId, code) {
  return crypto.createHmac('sha256', key).update(`${challengeId}:${code}`).digest('hex');
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// ---- Base32 (RFC 4648, no padding) — the format authenticator apps use for secrets ----------

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(text) {
  const clean = String(text).toUpperCase().replace(/[\s=-]/g, '');
  let bits = 0;
  let value = 0;
  const bytes = [];
  for (const char of clean) {
    const index = B32.indexOf(char);
    if (index === -1) throw new Error('Invalid base32 character');
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

// ---- TOTP (RFC 6238) --------------------------------------------------------------------------

const TOTP_STEP_SECONDS = 30;
const TOTP_DIGITS = 6;

/** A new 160-bit secret, base32 — what the user's authenticator app stores. */
const newTotpSecret = () => base32Encode(crypto.randomBytes(20));

function hotp(secretBase32, counter) {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const hmac = crypto.createHmac('sha1', base32Decode(secretBase32)).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0xf;
  const binary = hmac.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 10 ** TOTP_DIGITS).padStart(TOTP_DIGITS, '0');
}

function totp(secretBase32, timeMs = Date.now()) {
  return hotp(secretBase32, Math.floor(timeMs / 1000 / TOTP_STEP_SECONDS));
}

/** True if `code` matches the current 30s step or one step either side (clock drift). */
function verifyTotp(secretBase32, code, timeMs = Date.now()) {
  if (!/^\d{6}$/.test(String(code))) return false;
  const counter = Math.floor(timeMs / 1000 / TOTP_STEP_SECONDS);
  return [-1, 0, 1].some((drift) => safeEqual(hotp(secretBase32, counter + drift), code));
}

/** The otpauth:// URI an authenticator app scans as a QR code. */
function otpauthUrl({ issuer, account, secret }) {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({ secret, issuer, algorithm: 'SHA1', digits: String(TOTP_DIGITS), period: String(TOTP_STEP_SECONDS) });
  return `otpauth://totp/${label}?${params}`;
}

// ---- Encryption at rest (AES-256-GCM) ----------------------------------------------------------

/** 32-byte key from config: base64/hex of 32 bytes, or any other string (hashed to 32 bytes). */
function deriveKey(configured) {
  if (/^[0-9a-f]{64}$/i.test(configured)) return Buffer.from(configured, 'hex');
  const b64 = Buffer.from(configured, 'base64');
  if (b64.length === 32 && !configured.startsWith('derived:')) return b64;
  return crypto.createHash('sha256').update(configured).digest();
}

function encrypt(key, plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), data.toString('base64url')].join('.');
}

function decrypt(key, payload) {
  const [version, iv, tag, data] = String(payload).split('.');
  if (version !== 'v1') throw new Error('Unknown encrypted payload version');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'base64url'));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(data, 'base64url')), decipher.final()]).toString('utf8');
}

// ---- Display helpers ---------------------------------------------------------------------------

/** "jane.doe@example.com" -> "j•••e@example.com" — enough to recognise, not enough to harvest. */
function maskEmail(email) {
  const [local, domain] = String(email).split('@');
  if (!domain) return '•••';
  const shown = local.length <= 2 ? `${local[0] ?? ''}•••` : `${local[0]}•••${local[local.length - 1]}`;
  return `${shown}@${domain}`;
}

/** "+26876123456" -> "+268•••••456". */
function maskPhone(phone) {
  const p = String(phone);
  return p.length <= 7 ? '•••' : `${p.slice(0, 4)}${'•'.repeat(Math.max(3, p.length - 7))}${p.slice(-3)}`;
}

module.exports = {
  randomCode,
  hashCode,
  safeEqual,
  base32Encode,
  base32Decode,
  newTotpSecret,
  totp,
  verifyTotp,
  otpauthUrl,
  deriveKey,
  encrypt,
  decrypt,
  maskEmail,
  maskPhone,
};
