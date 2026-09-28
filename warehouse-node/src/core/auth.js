'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const argon2 = require('argon2');
const { unauthorized, forbidden } = require('./errors');
const { TAGS } = require('./cache/cache');
const { parseJson } = require('./models');

const API_KEY_HEADER = 'x-api-key';
const LAST_USED_TOUCH_INTERVAL_MS = 60_000;

/**
 * Authentication + authorisation primitives, shared by every module. Each guard is an async
 * function of the request that throws a 401/403 (see core/http.js createRoutes):
 *
 *  - authenticate            validates the access-token JWT, sets req.user
 *  - requirePermissions(...) checks permission KEYS (never role names) — run after authenticate
 *  - requireScopes(...)      the API-key equivalent — authenticates X-API-Key and checks scopes
 *
 * Caching (see core/cache/cache.js):
 *  - a user's effective permission keys are cached for a short TTL and invalidated on any
 *    role / user-role / role-permission change;
 *  - a verified API key is cached by the SHA-256 of the presented key. The original verified the
 *    key against every active key's argon2 hash on EVERY request (deliberately slow, O(active keys)).
 *    argon2 stays as the at-rest format; the cache just means the slow verify runs once per key per TTL.
 */
function createAuth({ config, db, cache }) {
  // ---- JWT --------------------------------------------------------------
  function signAccessToken(userId, email) {
    return jwt.sign({ sub: userId, email }, config.jwt.accessSecret, { expiresIn: config.jwt.accessExpiresIn });
  }

  function signRefreshToken(userId, jti) {
    return jwt.sign({ sub: userId, jti }, config.jwt.refreshSecret, { expiresIn: config.jwt.refreshExpiresIn });
  }

  function verifyRefreshToken(raw) {
    try {
      return jwt.verify(raw, config.jwt.refreshSecret, { algorithms: ['HS256'] });
    } catch {
      throw unauthorized('Invalid or expired refresh token');
    }
  }

  function extractBearer(req) {
    const header = req.headers.authorization;
    if (!header) return undefined;
    const [type, token] = header.split(' ');
    return type === 'Bearer' ? token : undefined;
  }

  async function authenticate(req) {
    const token = extractBearer(req);
    if (!token) throw unauthorized('Missing access token');
    try {
      const payload = jwt.verify(token, config.jwt.accessSecret, { algorithms: ['HS256'] });
      req.user = { id: payload.sub, email: payload.email };
    } catch {
      throw unauthorized('Invalid or expired access token');
    }
  }

  // ---- Permissions ------------------------------------------------------
  /**
   * The single source of truth for "what can this user do" — the permission guard (enforcement) and
   * GET /auth/me (what the client is told) both call this, so they can never disagree.
   */
  function resolveEffectivePermissionKeys(userId) {
    return cache.wrap(
      `perm:${userId}`,
      { ttlMs: config.cache.permissionsTtlMs, tags: [TAGS.PERMISSIONS] },
      async () => {
        const rows = await db.query(
          `SELECT DISTINCT p.\`key\` AS \`key\`
             FROM user_roles ur
             JOIN role_permissions rp ON rp.role_id = ur.role_id
             JOIN permissions p ON p.id = rp.permission_id
            WHERE ur.user_id = ?`,
          [userId],
        );
        return rows.map((r) => r.key);
      },
    );
  }

  function requirePermissions(...required) {
    return async function permissionGuard(req) {
      if (!req.user) throw unauthorized('Missing authenticated user');
      if (required.length === 0) return;
      const granted = await resolveEffectivePermissionKeys(req.user.id);
      if (!required.every((key) => granted.includes(key))) throw forbidden('Insufficient permissions');
    };
  }

  // ---- API keys ---------------------------------------------------------
  const lastTouched = new Map(); // keyId -> epoch ms of the last lastUsedAt write

  async function verifyApiKey(rawKey) {
    const digest = crypto.createHash('sha256').update(rawKey).digest('hex');
    return cache.wrap(`apikey:${digest}`, { ttlMs: config.cache.apiKeyTtlMs, tags: [TAGS.API_KEYS] }, async () => {
      const candidates = await db.query(
        'SELECT id, name, key_hash AS keyHash, scopes FROM api_keys WHERE is_active = true',
      );
      for (const candidate of candidates) {
        if (await argon2.verify(candidate.keyHash, rawKey)) {
          return { id: candidate.id, name: candidate.name, scopes: parseJson(candidate.scopes) };
        }
      }
      return undefined; // never cached: an unknown key must be re-checked each time
    });
  }

  function requireScopes(...required) {
    return async function apiKeyGuard(req) {
      const rawKey = req.headers[API_KEY_HEADER];
      if (!rawKey || typeof rawKey !== 'string') throw unauthorized('Missing API key');

      const matched = await verifyApiKey(rawKey);
      if (!matched) throw unauthorized('Invalid or inactive API key');

      if (!required.every((scope) => matched.scopes.includes(scope))) {
        throw forbidden('API key lacks the required scope');
      }

      req.apiKey = { id: matched.id, name: matched.name, scopes: matched.scopes };

      // Fire-and-forget and throttled: bookkeeping must never slow down or fail the request.
      const now = Date.now();
      if (now - (lastTouched.get(matched.id) ?? 0) > LAST_USED_TOUCH_INTERVAL_MS) {
        lastTouched.set(matched.id, now);
        void db.exec('UPDATE api_keys SET last_used_at = ? WHERE id = ?', [new Date(), matched.id]).catch(() => {});
      }
    };
  }

  return {
    authenticate,
    requirePermissions,
    requireScopes,
    resolveEffectivePermissionKeys,
    signAccessToken,
    signRefreshToken,
    verifyRefreshToken,
  };
}

module.exports = { createAuth };
