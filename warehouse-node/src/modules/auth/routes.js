'use strict';

const { obj, str, nonEmpty } = require('../../core/schema');

const emailSchema = str({ format: 'email' });

async function authRoutes(app) {
  const { auth: authService } = app.services;

  // Public: no authenticate hook.
  app.post(
    '/login',
    { schema: { body: obj({ email: emailSchema, password: nonEmpty() }, ['email', 'password']) } },
    async (request, reply) => {
      const result = await authService.login(request.body);
      request.auditEntityId = result.user.id;
      request.auditAction = 'LOGIN';
      reply.code(200);
      return result;
    },
  );

  app.post(
    '/refresh',
    { schema: { body: obj({ refreshToken: nonEmpty() }, ['refreshToken']) } },
    async (request, reply) => {
      const result = await authService.refresh(request.body.refreshToken);
      request.auditEntityId = result.user.id;
      request.auditAction = 'REFRESH';
      reply.code(200);
      return result;
    },
  );

  app.post(
    '/logout',
    { schema: { body: obj({ refreshToken: nonEmpty() }, ['refreshToken']) } },
    async (request, reply) => {
      request.auditAction = 'LOGOUT';
      reply.code(200);
      return authService.logout(request.body.refreshToken);
    },
  );

  // Requires a valid access token but no specific permission.
  app.get('/me', { onRequest: [app.authenticate] }, async (request) => authService.me(request.user.id));
}

module.exports = authRoutes;
