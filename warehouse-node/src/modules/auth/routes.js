'use strict';

const { obj, str, nonEmpty, uuid, opt, enumOf } = require('../../core/schema');
const { OtpChannel } = require('../../core/enums');
const { OTP_ACTIONS } = require('../../catalog/otp-actions');

const emailSchema = str({ format: 'email' });
const code = { type: 'string', pattern: '^\\s*\\d{6}\\s*$' };

function authRoutes(app) {
  const { auth: authService, otp } = app.services;
  const { authenticate } = app;

  // ---- Public: sign-in ------------------------------------------------------------------------

  app.post(
    '/login',
    { schema: { body: obj({ email: emailSchema, password: nonEmpty() }, ['email', 'password']) } },
    async (request, res) => {
      const result = await authService.login(request.body);
      res.status(200);
      if (result.mfaRequired) {
        // Password was right but sign-in is not finished: no tokens yet.
        const { userId, ...challenge } = result;
        request.auditEntityId = userId;
        request.auditAction = 'LOGIN_MFA_CHALLENGE';
        return challenge;
      }
      request.auditEntityId = result.user.id;
      request.auditAction = 'LOGIN';
      return result;
    },
  );

  app.post(
    '/mfa/verify',
    { schema: { body: obj({ challengeId: uuid, code }, ['challengeId', 'code']) } },
    async (request, res) => {
      const result = await authService.verifyMfa(request.body);
      request.auditEntityId = result.user.id;
      request.auditAction = 'LOGIN';
      request.auditBody = { challengeId: request.body.challengeId };
      res.status(200);
      return result;
    },
  );

  app.post(
    '/mfa/resend',
    {
      schema: {
        body: obj({ challengeId: uuid, channel: opt({ type: 'string', enum: ['EMAIL', 'SMS'] }) }, ['challengeId']),
      },
    },
    async (request, res) => {
      const { userId, ...challenge } = await authService.resendMfa(request.body);
      request.auditEntityId = userId;
      request.auditAction = 'LOGIN_MFA_RESEND';
      res.status(200);
      return challenge;
    },
  );

  app.post(
    '/refresh',
    { schema: { body: obj({ refreshToken: nonEmpty() }, ['refreshToken']) } },
    async (request, res) => {
      const result = await authService.refresh(request.body.refreshToken);
      request.auditEntityId = result.user.id;
      request.auditAction = 'REFRESH';
      res.status(200);
      return result;
    },
  );

  app.post(
    '/logout',
    { schema: { body: obj({ refreshToken: nonEmpty() }, ['refreshToken']) } },
    async (request, res) => {
      request.auditAction = 'LOGOUT';
      res.status(200);
      return authService.logout(request.body.refreshToken);
    },
  );

  // Requires a valid access token but no specific permission.
  app.get('/me', { onRequest: [authenticate] }, async (request) => authService.me(request.user.id));

  // ---- One-time code to confirm a sensitive action (see catalog/otp-actions.js) ---------------

  app.post(
    '/otp',
    {
      onRequest: [authenticate],
      schema: {
        body: obj(
          {
            action: { type: 'string', enum: Object.keys(OTP_ACTIONS) },
            targetId: opt(str()),
            channel: opt(enumOf(OtpChannel)),
          },
          ['action'],
        ),
      },
    },
    async (request, res) => {
      const challenge = await authService.requestActionCode(request.user.id, request.body);
      request.auditEntity = 'otp_challenges';
      request.auditEntityId = challenge.challengeId;
      request.auditAction = 'OTP_REQUEST';
      res.status(201);
      return challenge;
    },
  );

  // ---- Own MFA settings --------------------------------------------------------------------------

  app.post(
    '/mfa/setup',
    { onRequest: [authenticate], schema: { body: obj({ method: enumOf(OtpChannel) }, ['method']) } },
    async (request, res) => {
      const result = await authService.startMfaSetup(request.user.id, request.body);
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      request.auditAction = 'MFA_SETUP_START';
      res.status(200);
      return result; // for TOTP this is the one time the secret is shown — never audited
    },
  );

  app.post(
    '/mfa/setup/confirm',
    { onRequest: [authenticate], schema: { body: obj({ challengeId: uuid, code }, ['challengeId', 'code']) } },
    async (request, res) => {
      const result = await authService.confirmMfaSetup(request.user.id, request.body);
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      request.auditAction = 'MFA_ENABLE';
      request.auditBody = result;
      res.status(200);
      return result;
    },
  );

  app.post(
    '/mfa/disable',
    { onRequest: [authenticate], preHandler: [otp.requireOtp('mfa.disable')] },
    async (request, res) => {
      const result = await authService.disableMfa(request.user.id);
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      request.auditAction = 'MFA_DISABLE';
      res.status(200);
      return result;
    },
  );
}

module.exports = authRoutes;
