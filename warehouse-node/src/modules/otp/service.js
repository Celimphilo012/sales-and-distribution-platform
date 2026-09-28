'use strict';

const { badRequest, forbidden, preconditionRequired, tooManyRequests, serviceUnavailable } = require('../../core/errors');
const { cols } = require('../../core/models');
const { randomCode, hashCode, safeEqual, verifyTotp, decrypt, deriveKey, maskEmail, maskPhone } = require('../../core/crypto');
const { OTP_ACTIONS } = require('../../catalog/otp-actions');

const USER_CONTACT_FIELDS = ['id', 'email', 'fullName', 'phone', 'notifyChannel', 'mfaMethod', 'totpSecret', 'status'];

/**
 * One-time codes, for three purposes:
 *   ACTION     step-up confirmation of a sensitive action (catalog/otp-actions.js), bound to that
 *              action AND the target record, so a code for "approve adjustment A" can't approve B
 *   LOGIN      the second step of sign-in when the user has MFA turned on
 *   MFA_SETUP  proving the user controls the email/phone/authenticator app they are enrolling
 *
 * Email/SMS codes are 6 random digits, stored only as a keyed hash, valid for config.otp.codeTtlMs,
 * single-use, and locked after config.otp.maxAttempts wrong guesses. Authenticator-app (TOTP)
 * challenges carry no stored code — the app's current code is checked against the user's secret.
 * Requests are rate-limited per user (SMS costs money, and it bounds guessing).
 */
function createOtpService({ db, models, config, notifier }) {
  const encryptionKey = deriveKey(config.secretsKey);
  const hmacKey = deriveKey(`otp-hash:${config.secretsKey}`);

  async function loadUser(userId) {
    const user = await db.one(`SELECT ${cols('user', 'u', USER_CONTACT_FIELDS)} FROM users u WHERE u.id = ?`, [userId]);
    if (!user) throw forbidden('User not found');
    return user;
  }

  /** Channels this user can receive a code on right now. */
  function availableChannels(user) {
    const channels = ['EMAIL'];
    if (user.phone) channels.push('SMS');
    if (user.mfaMethod === 'TOTP' && user.totpSecret) channels.push('TOTP');
    return channels;
  }

  /** Default channel: the authenticator app if enrolled, else the user's notification preference. */
  function defaultChannel(user) {
    if (user.mfaMethod === 'TOTP' && user.totpSecret) return 'TOTP';
    if (user.notifyChannel === 'SMS' && user.phone) return 'SMS';
    return 'EMAIL';
  }

  const destinationFor = (user, channel) =>
    channel === 'EMAIL' ? maskEmail(user.email) : channel === 'SMS' ? maskPhone(user.phone) : 'your authenticator app';

  async function enforceRateLimit(userId) {
    const since = new Date(Date.now() - config.otp.windowMs);
    const { n } = await db.one(
      "SELECT COUNT(*) AS n FROM otp_challenges WHERE user_id = ? AND created_at >= ? AND channel <> 'TOTP'",
      [userId, since],
    );
    if (n >= config.otp.maxPerWindow) {
      throw tooManyRequests('Too many codes requested — wait a few minutes and try again');
    }
  }

  function messageFor(purpose, action, code) {
    const minutes = Math.round(config.otp.codeTtlMs / 60_000);
    if (purpose === 'LOGIN') {
      return {
        subject: `${config.appName} sign-in code`,
        text: `${config.appName}: your sign-in code is ${code}. It expires in ${minutes} minutes. If you are not signing in, change your password.`,
      };
    }
    if (purpose === 'MFA_SETUP') {
      return {
        subject: `${config.appName} verification code`,
        text: `${config.appName}: your verification code is ${code}. It expires in ${minutes} minutes.`,
      };
    }
    return {
      subject: `${config.appName} confirmation code`,
      text: `${config.appName}: your code to ${OTP_ACTIONS[action]} is ${code}. It expires in ${minutes} minutes. If this wasn't you, tell your administrator.`,
    };
  }

  /**
   * Creates a challenge and, for EMAIL/SMS, delivers the code. `destination` overrides where the
   * code goes (MFA setup verifies a phone/email before it is switched on).
   * Returns { challengeId, channel, destination, expiresAt, availableChannels }.
   */
  async function issue({ userId, purpose, channel, action = null, targetId = null, pendingSecret = null, user: preloaded }) {
    const user = preloaded ?? (await loadUser(userId));
    if (purpose === 'ACTION' && !OTP_ACTIONS[action]) throw badRequest(`Unknown action "${action}"`);

    const chosen = channel ?? defaultChannel(user);
    const allowed = purpose === 'MFA_SETUP' ? ['EMAIL', 'SMS', 'TOTP'] : availableChannels(user);
    if (!allowed.includes(chosen)) {
      throw badRequest(
        chosen === 'SMS'
          ? 'No phone number on your account — add one in Settings to receive codes by SMS'
          : chosen === 'TOTP'
            ? 'No authenticator app is set up on your account'
            : `Channel "${chosen}" is not available`,
      );
    }
    if (chosen === 'SMS' && !user.phone) throw badRequest('No phone number on your account — add one in Settings first');
    if (chosen !== 'TOTP') await enforceRateLimit(user.id);

    const expiresAt = new Date(Date.now() + config.otp.codeTtlMs);
    const challenge = await models.insert('otpChallenge', {
      userId: user.id,
      purpose,
      channel: chosen,
      action,
      targetId,
      pendingSecret,
      expiresAt,
    });

    if (chosen !== 'TOTP') {
      const code = randomCode();
      await db.exec('UPDATE otp_challenges SET code_hash = ? WHERE id = ?', [hashCode(hmacKey, challenge.id, code), challenge.id]);
      const { subject, text } = messageFor(purpose, action, code);
      const delivery = await notifier.send({
        userId: user.id,
        event: `otp.${purpose.toLowerCase()}`,
        channel: chosen,
        to: chosen === 'SMS' ? user.phone : user.email,
        subject,
        text,
        sensitive: true,
      });
      if (!delivery.ok) {
        throw serviceUnavailable(
          `Could not send the code by ${chosen === 'SMS' ? 'SMS' : 'email'} — try ${chosen === 'SMS' ? 'email' : 'SMS'} instead, or try again shortly`,
        );
      }
    }

    return {
      challengeId: challenge.id,
      channel: chosen,
      destination: destinationFor(user, chosen),
      expiresAt,
      availableChannels: availableChannels(user),
    };
  }

  /**
   * Checks `code` against a challenge and consumes it. `expect` = { userId, purpose, action?, targetId? }.
   * Throws 403 (with otpInvalid) for a wrong/expired/used code. Returns the challenge row.
   */
  async function verify(challengeId, code, expect, invalidExtra = {}) {
    const invalid = (message) => forbidden(message, { otpInvalid: true, ...invalidExtra });
    const challenge = await models.findById('otpChallenge', challengeId);
    if (
      !challenge ||
      challenge.userId !== expect.userId ||
      challenge.purpose !== expect.purpose ||
      (expect.action !== undefined && challenge.action !== expect.action) ||
      (expect.targetId !== undefined && (challenge.targetId ?? null) !== (expect.targetId ?? null))
    ) {
      throw invalid('This code is not valid for this action — request a new one');
    }
    if (challenge.consumedAt) throw invalid('This code has already been used — request a new one');
    if (challenge.expiresAt.getTime() < Date.now()) throw invalid('This code has expired — request a new one');
    if (challenge.attempts >= config.otp.maxAttempts) throw invalid('Too many wrong attempts — request a new code');

    // Count the attempt first (atomically), so parallel guesses can't exceed the limit.
    await db.exec('UPDATE otp_challenges SET attempts = attempts + 1 WHERE id = ?', [challengeId]);

    let ok;
    const clean = String(code ?? '').replace(/\s/g, '');
    if (challenge.channel === 'TOTP') {
      let secret;
      if (challenge.pendingSecret) secret = decrypt(encryptionKey, challenge.pendingSecret);
      else {
        const user = await loadUser(challenge.userId);
        if (!user.totpSecret) throw invalid('No authenticator app is set up on your account');
        secret = decrypt(encryptionKey, user.totpSecret);
      }
      ok = verifyTotp(secret, clean);
    } else {
      ok = Boolean(challenge.codeHash) && safeEqual(hashCode(hmacKey, challengeId, clean), challenge.codeHash);
    }
    if (!ok) throw invalid('Incorrect code — check it and try again');

    // Single use: only the request that flips consumed_at from NULL wins.
    const consumed = await db.exec('UPDATE otp_challenges SET consumed_at = ? WHERE id = ? AND consumed_at IS NULL', [
      new Date(),
      challengeId,
    ]);
    if (consumed.affectedRows !== 1) throw invalid('This code has already been used — request a new one');
    return challenge;
  }

  /**
   * Route guard: the request must carry X-OTP-Challenge + X-OTP-Code for a challenge issued for
   * `action` on this exact target (the route's last path param). `when(req)` limits it to some
   * requests (e.g. a PATCH that deactivates). A missing code answers 428 with { otpRequired,
   * action, targetId, availableChannels } so the client knows to prompt and retry.
   */
  function requireOtp(action, { when } = {}) {
    if (!OTP_ACTIONS[action]) throw new Error(`requireOtp: "${action}" is not in catalog/otp-actions.js`);
    return async function otpGuard(req) {
      if (!config.otp.enabled) return;
      if (when && !when(req)) return;
      const params = Object.values(req.params ?? {});
      const targetId = params.length ? params[params.length - 1] : null;
      const extra = { otpRequired: true, action, targetId };

      const challengeId = req.headers['x-otp-challenge'];
      const code = req.headers['x-otp-code'];
      if (!challengeId || !code) {
        const user = await loadUser(req.user.id);
        throw preconditionRequired(`Confirm with a one-time code to ${OTP_ACTIONS[action]}`, {
          ...extra,
          availableChannels: availableChannels(user),
          defaultChannel: defaultChannel(user),
        });
      }
      await verify(String(challengeId), String(code), { userId: req.user.id, purpose: 'ACTION', action, targetId }, extra);
    };
  }

  return { issue, verify, requireOtp, loadUser, availableChannels, defaultChannel, destinationFor, encryptionKey };
}

module.exports = { createOtpService };
