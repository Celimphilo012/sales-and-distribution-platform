'use strict';

const { obj, nonEmpty, arrayOf, uuidParams } = require('../../core/schema');
const { API_KEY_SCOPES } = require('../../core/scopes');

const createBody = obj(
  {
    name: nonEmpty(),
    scopes: arrayOf({ type: 'string', enum: API_KEY_SCOPES }, { minItems: 1, uniqueItems: true }),
  },
  ['name', 'scopes'],
);

/**
 * Admin-only JWT-guarded management of the external API's keys — separate from the keys
 * themselves, which authenticate via the scope guard on /api/v1/*. Gated behind users.manage.
 */
async function apiKeysRoutes(app) {
  const { apiKeys } = app.services;
  const guard = [app.authenticate, app.requirePermissions('users.manage')];

  app.get('/', { onRequest: guard }, async () => apiKeys.findAll());

  app.post('/', { onRequest: guard, schema: { body: createBody } }, async (request) => {
    const created = await apiKeys.create(request.body, request.user.id);
    request.auditEntityId = created.id;
    // Never write the raw key into the audit log.
    request.auditBody = { name: request.body.name, scopes: request.body.scopes };
    return created;
  });

  app.post('/:id/revoke', { onRequest: guard, schema: { params: uuidParams('id') } }, async (request, reply) => {
    request.auditOldValue = await apiKeys.getExisting(request.params.id);
    request.auditAction = 'REVOKE';
    reply.code(201);
    return apiKeys.revoke(request.params.id);
  });
}

module.exports = apiKeysRoutes;
