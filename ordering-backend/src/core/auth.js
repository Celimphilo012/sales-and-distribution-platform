'use strict';

const jwt = require('jsonwebtoken');
const { unauthorized, forbidden } = require('./errors');

/**
 * Authentication + authorisation guards, shared by every module. Each guard is an async function
 * of the request that throws a 401/403 (see core/http.js createRoutes):
 *
 *  - authenticate            validates the access-token JWT, sets req.user
 *  - requirePermissions(...) checks permission KEYS (never role names — rule 1); runs after authenticate
 */
function createAuth({ config, db }) {
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

  async function authenticate(req) {
    const header = req.headers.authorization;
    const [type, token] = header ? header.split(' ') : [];
    if (type !== 'Bearer' || !token) throw unauthorized('Missing access token');
    try {
      const payload = jwt.verify(token, config.jwt.accessSecret, { algorithms: ['HS256'] });
      req.user = { id: payload.sub, email: payload.email };
    } catch {
      throw unauthorized('Invalid or expired access token');
    }
  }

  /**
   * The single source of truth for "what can this user do" — the permission guard (enforcement) and
   * GET /auth/me (what the client is told) both call this, so they can never disagree.
   */
  async function resolveEffectivePermissionKeys(userId) {
    const rows = await db.query(
      `SELECT DISTINCT p.\`key\` AS \`key\`
         FROM user_roles ur
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id
        WHERE ur.user_id = ?`,
      [userId],
    );
    return rows.map((r) => r.key);
  }

  async function hasPermission(userId, key) {
    return (await resolveEffectivePermissionKeys(userId)).includes(key);
  }

  function requirePermissions(...required) {
    return async function permissionGuard(req) {
      if (!req.user) throw unauthorized('Missing authenticated user');
      if (required.length === 0) return;
      const granted = await resolveEffectivePermissionKeys(req.user.id);
      if (!required.every((key) => granted.includes(key))) throw forbidden('Insufficient permissions');
    };
  }

  return {
    authenticate,
    requirePermissions,
    resolveEffectivePermissionKeys,
    hasPermission,
    signAccessToken,
    signRefreshToken,
    verifyRefreshToken,
  };
}

module.exports = { createAuth };
