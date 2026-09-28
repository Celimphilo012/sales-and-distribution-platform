'use strict';

const argon2 = require('argon2');
const { badRequest, conflict, unauthorized } = require('../../core/errors');
const { parseDurationMs } = require('../../core/duration');
const { encrypt, newTotpSecret, otpauthUrl } = require('../../core/crypto');

function createAuthService({ db, models, auth, config, otp }) {
  const publicUser = (user) => ({ id: user.id, email: user.email, fullName: user.fullName });

  async function issueRefreshToken(userId) {
    const expiresAt = new Date(Date.now() + parseDurationMs(config.jwt.refreshExpiresIn));
    const row = await models.insert('refreshToken', { userId, tokenHash: 'pending', expiresAt });
    const token = auth.signRefreshToken(userId, row.id);
    const tokenHash = await argon2.hash(token);
    await db.exec('UPDATE refresh_tokens SET token_hash = ? WHERE id = ?', [tokenHash, row.id]);
    return { token, id: row.id };
  }

  async function issueSession(user) {
    const accessToken = auth.signAccessToken(user.id, user.email);
    const { token: refreshToken } = await issueRefreshToken(user.id);
    return { accessToken, refreshToken, user: publicUser(user) };
  }

  const findUserByEmail = (email) =>
    db.one(
      `SELECT id, email, password_hash AS passwordHash, full_name AS fullName, status, mfa_method AS mfaMethod
         FROM users WHERE email = ?`,
      [email],
    );

  /**
   * Password check. Without MFA this returns the session directly. With MFA it returns
   * { mfaRequired: true, challengeId, channel, destination, availableChannels, expiresAt } and NO
   * tokens — the client finishes with POST /auth/mfa/verify. (`userId` is for the audit row only;
   * the route strips it from the response.)
   */
  async function login({ email, password }) {
    const user = await findUserByEmail(email);
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Invalid email or password');

    if (!(await argon2.verify(user.passwordHash, password))) throw unauthorized('Invalid email or password');

    if (user.mfaMethod === 'NONE') return issueSession(user);

    const challenge = await otp.issue({ userId: user.id, purpose: 'LOGIN', channel: user.mfaMethod });
    return { mfaRequired: true, userId: user.id, ...loginChallengeView(user.mfaMethod, challenge) };
  }

  /** At sign-in, an EMAIL/SMS user may switch between the two; a TOTP user only has the app. */
  function loginChallengeView(mfaMethod, challenge) {
    const choices = mfaMethod === 'TOTP' ? ['TOTP'] : challenge.availableChannels.filter((c) => c !== 'TOTP');
    return { ...challenge, availableChannels: choices };
  }

  async function verifyMfa({ challengeId, code }) {
    const challengeRow = await models.findById('otpChallenge', challengeId);
    if (!challengeRow || challengeRow.purpose !== 'LOGIN') throw unauthorized('Sign-in code is not valid — sign in again');
    await otp.verify(challengeId, code, { userId: challengeRow.userId, purpose: 'LOGIN' });

    const user = await models.findById('user', challengeRow.userId);
    if (!user || user.status !== 'ACTIVE') throw unauthorized('Account is no longer active');
    return issueSession(user);
  }

  /** Sends a fresh sign-in code (optionally on the other channel) for an unfinished MFA sign-in. */
  async function resendMfa({ challengeId, channel }) {
    const previous = await models.findById('otpChallenge', challengeId);
    if (!previous || previous.purpose !== 'LOGIN' || previous.consumedAt || previous.expiresAt.getTime() < Date.now()) {
      throw unauthorized('This sign-in has expired — sign in again');
    }
    const user = await otp.loadUser(previous.userId);
    if (user.mfaMethod === 'TOTP') throw badRequest('Use the code shown in your authenticator app');
    const next = channel ?? previous.channel;
    if (next === 'TOTP') throw badRequest('Choose EMAIL or SMS');

    const challenge = await otp.issue({ userId: user.id, purpose: 'LOGIN', channel: next, user });
    await db.exec('UPDATE otp_challenges SET consumed_at = ? WHERE id = ? AND consumed_at IS NULL', [new Date(), previous.id]);
    return { mfaRequired: true, userId: user.id, ...loginChallengeView(user.mfaMethod, challenge) };
  }

  async function refresh(rawRefreshToken) {
    const payload = auth.verifyRefreshToken(rawRefreshToken);

    const existing = await models.findById('refreshToken', payload.jti);
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

  /**
   * The caller's own identity + effective permissions + contact/MFA settings, always resolved from
   * the authenticated userId. Permissions come from the same helper the permission guard uses, so
   * this can never disagree with what is actually enforced.
   */
  async function me(userId) {
    const user = await db.one(
      `SELECT id, email, full_name AS fullName, phone, notify_channel AS notifyChannel, mfa_method AS mfaMethod, status
         FROM users WHERE id = ?`,
      [userId],
    );
    if (!user) throw unauthorized('User not found');

    const roles = await db.query(
      'SELECT r.id, r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = ?',
      [userId],
    );
    const permissions = await auth.resolveEffectivePermissionKeys(userId);
    return { ...user, roles, permissions };
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

  // ---- Step-up codes ----------------------------------------------------------------------------

  /** Sends (or, for the authenticator app, just opens) a code to confirm one sensitive action. */
  const requestActionCode = (userId, { action, targetId, channel }) =>
    otp.issue({ userId, purpose: 'ACTION', action, targetId: targetId ?? null, channel: channel ?? undefined });

  // ---- MFA enrolment (self-service) ---------------------------------------------------------------

  /**
   * Starts turning MFA on. EMAIL/SMS: a code goes to that channel. TOTP: a new secret is generated
   * (returned once, with the otpauth:// URL for the QR code) and held encrypted on the challenge
   * until the user proves their app produces matching codes.
   */
  async function startMfaSetup(userId, { method }) {
    const user = await otp.loadUser(userId);
    if (method === 'SMS' && !user.phone) throw badRequest('Add a phone number in Settings before choosing SMS');

    if (method !== 'TOTP') return otp.issue({ userId, purpose: 'MFA_SETUP', channel: method, user });

    const secret = newTotpSecret();
    const challenge = await otp.issue({
      userId,
      purpose: 'MFA_SETUP',
      channel: 'TOTP',
      pendingSecret: encrypt(otp.encryptionKey, secret),
      user,
    });
    return { ...challenge, secret, otpauthUrl: otpauthUrl({ issuer: config.appName, account: user.email, secret }) };
  }

  async function confirmMfaSetup(userId, { challengeId, code }) {
    const challenge = await otp.verify(challengeId, code, { userId, purpose: 'MFA_SETUP' });
    await models.update(
      'user',
      userId,
      {
        mfaMethod: challenge.channel,
        // Switching away from the app forgets its secret; enrolling the app stores the verified one.
        totpSecret: challenge.channel === 'TOTP' ? challenge.pendingSecret : null,
      },
      'User',
    );
    return { mfaMethod: challenge.channel };
  }

  /** Turning MFA off is itself step-up protected (route guard 'mfa.disable'). */
  async function disableMfa(userId) {
    const user = await otp.loadUser(userId);
    if (user.mfaMethod === 'NONE') throw conflict('Sign-in verification is already off');
    await models.update('user', userId, { mfaMethod: 'NONE', totpSecret: null }, 'User');
    return { mfaMethod: 'NONE' };
  }

  return {
    login,
    verifyMfa,
    resendMfa,
    refresh,
    me,
    logout,
    requestActionCode,
    startMfaSetup,
    confirmMfaSetup,
    disableMfa,
  };
}

module.exports = { createAuthService };
