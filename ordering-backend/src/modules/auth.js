'use strict';

const argon2 = require('argon2');
const { unauthorized } = require('../core/errors');
const { parseDurationMs } = require('../core/duration');
const { obj, str, nonEmpty } = require('../core/schema');

function createAuthService({ db, models, auth, config }) {
  const publicUser = (user) => ({ id: user.id, email: user.email, fullName: user.fullName });

  async function issueRefreshToken(userId) {
    const expiresAt = new Date(Date.now() + parseDurationMs(config.jwt.refreshExpiresIn));
    const row = await models.insert('refreshToken', { userId, tokenHash: 'pending', expiresAt });
    const token = auth.signRefreshToken(userId, row.id);
    await db.exec('UPDATE refresh_tokens SET token_hash = ? WHERE id = ?', [await argon2.hash(token), row.id]);
    return { token, id: row.id };
  }

  async function login({ email, password }) {
    const user = await db.one(
      'SELECT id, email, password_hash AS passwordHash, full_name AS fullName, status FROM users WHERE email = ?',
      [email],
    );
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Invalid email or password');
    if (!(await argon2.verify(user.passwordHash, password))) throw unauthorized('Invalid email or password');

    const accessToken = auth.signAccessToken(user.id, user.email);
    const { token: refreshToken } = await issueRefreshToken(user.id);
    return { accessToken, refreshToken, user: publicUser(user) };
  }

  async function refresh(rawRefreshToken) {
    const payload = auth.verifyRefreshToken(rawRefreshToken);
    const existing = await models.findById('refreshToken', payload.jti);
    if (!existing || existing.userId !== payload.sub || existing.revokedAt || existing.expiresAt.getTime() < Date.now()) {
      throw unauthorized('Refresh token is no longer valid');
    }
    if (!(await argon2.verify(existing.tokenHash, rawRefreshToken))) throw unauthorized('Refresh token is no longer valid');

    const user = await models.findById('user', payload.sub);
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Account is no longer active');

    const accessToken = auth.signAccessToken(user.id, user.email);
    const { token: newRefreshToken, id: newRowId } = await issueRefreshToken(user.id);
    await db.exec('UPDATE refresh_tokens SET revoked_at = ?, replaced_by_token_id = ? WHERE id = ?', [
      new Date(),
      newRowId,
      existing.id,
    ]);
    return { accessToken, refreshToken: newRefreshToken, user: publicUser(user) };
  }

  /** Own identity + effective permissions, from the same resolver the permission guard uses. */
  async function me(userId) {
    const user = await db.one('SELECT id, email, full_name AS fullName, status FROM users WHERE id = ?', [userId]);
    if (!user) throw unauthorized('User not found');
    const roles = await db.query(
      'SELECT r.id, r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = ?',
      [userId],
    );
    return { ...user, roles, permissions: await auth.resolveEffectivePermissionKeys(userId) };
  }

  async function logout(rawRefreshToken) {
    try {
      const payload = auth.verifyRefreshToken(rawRefreshToken);
      await db.exec('UPDATE refresh_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL', [new Date(), payload.jti]);
    } catch {
      // Logout is idempotent: an already-invalid token is not an error.
    }
    return { success: true };
  }

  return { login, refresh, me, logout };
}

const refreshBody = obj({ refreshToken: nonEmpty() }, ['refreshToken']);

function authRoutes(app) {
  const service = app.services.auth;

  app.post(
    '/login',
    { schema: { body: obj({ email: str({ format: 'email' }), password: nonEmpty() }, ['email', 'password']) } },
    async (request, res) => {
      const result = await service.login(request.body);
      request.auditEntityId = result.user.id;
      request.auditAction = 'LOGIN';
      res.status(200);
      return result;
    },
  );

  app.post('/refresh', { schema: { body: refreshBody } }, async (request, res) => {
    const result = await service.refresh(request.body.refreshToken);
    request.auditEntityId = result.user.id;
    request.auditAction = 'REFRESH';
    res.status(200);
    return result;
  });

  app.post('/logout', { schema: { body: refreshBody } }, async (request, res) => {
    request.auditAction = 'LOGOUT';
    res.status(200);
    return service.logout(request.body.refreshToken);
  });

  app.get('/me', { onRequest: [app.authenticate] }, async (request) => service.me(request.user.id));
}

module.exports = { createAuthService, authRoutes };
