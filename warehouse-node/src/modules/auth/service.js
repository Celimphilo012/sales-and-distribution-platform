'use strict';

const argon2 = require('argon2');
const { unauthorized } = require('../../core/errors');
const { parseDurationMs } = require('../../core/duration');

function createAuthService({ prisma, auth, config }) {
  const publicUser = (user) => ({ id: user.id, email: user.email, fullName: user.fullName });

  async function issueRefreshToken(userId) {
    const expiresAt = new Date(Date.now() + parseDurationMs(config.jwt.refreshExpiresIn));
    const row = await prisma.refreshToken.create({ data: { userId, tokenHash: 'pending', expiresAt } });
    const token = auth.signRefreshToken(userId, row.id);
    const tokenHash = await argon2.hash(token);
    await prisma.refreshToken.update({ where: { id: row.id }, data: { tokenHash } });
    return { token, id: row.id };
  }

  async function login({ email, password }) {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Invalid email or password');

    if (!(await argon2.verify(user.passwordHash, password))) throw unauthorized('Invalid email or password');

    const accessToken = auth.signAccessToken(user.id, user.email);
    const { token: refreshToken } = await issueRefreshToken(user.id);
    return { accessToken, refreshToken, user: publicUser(user) };
  }

  async function refresh(rawRefreshToken) {
    const payload = auth.verifyRefreshToken(rawRefreshToken);

    const existing = await prisma.refreshToken.findUnique({ where: { id: payload.jti } });
    if (
      !existing ||
      existing.userId !== payload.sub ||
      existing.revokedAt ||
      existing.expiresAt.getTime() < Date.now()
    ) {
      throw unauthorized('Refresh token is no longer valid');
    }

    if (!(await argon2.verify(existing.tokenHash, rawRefreshToken))) {
      throw unauthorized('Refresh token is no longer valid');
    }

    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Account is no longer active');

    const accessToken = auth.signAccessToken(user.id, user.email);
    const { token: newRefreshToken, id: newRowId } = await issueRefreshToken(user.id);

    await prisma.refreshToken.update({
      where: { id: existing.id },
      data: { revokedAt: new Date(), replacedByTokenId: newRowId },
    });

    return { accessToken, refreshToken: newRefreshToken, user: publicUser(user) };
  }

  /**
   * The caller's own identity + effective permissions, always resolved from the
   * authenticated userId. Permissions come from the same helper the permission
   * guard uses, so this can never disagree with what is actually enforced.
   */
  async function me(userId) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        fullName: true,
        status: true,
        userRoles: { select: { role: { select: { id: true, name: true } } } },
      },
    });
    if (!user) throw unauthorized('User not found');

    const { userRoles, ...profile } = user;
    const permissions = await auth.resolveEffectivePermissionKeys(userId);
    return { ...profile, roles: userRoles.map((ur) => ur.role), permissions };
  }

  async function logout(rawRefreshToken) {
    try {
      const payload = auth.verifyRefreshToken(rawRefreshToken);
      await prisma.refreshToken.updateMany({
        where: { id: payload.jti, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    } catch {
      // Logout is idempotent: an already-invalid token is not an error.
    }
    return { success: true };
  }

  return { login, refresh, me, logout };
}

module.exports = { createAuthService };
