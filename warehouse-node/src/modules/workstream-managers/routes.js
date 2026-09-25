'use strict';

const { obj, uuid, uuidParams } = require('../../core/schema');

/**
 * Who can manage a given workstream's catalogue — separate from the workstream record itself
 * (workstreams.manage) and from the catalogue mutations this assignment scopes (products.manage).
 * Gated workstreams.assign throughout.
 */
async function workstreamManagersRoutes(app) {
  const { workstreamManagers } = app.services;
  const guard = [app.authenticate, app.requirePermissions('workstreams.assign')];

  app.get('/', { onRequest: guard, schema: { params: uuidParams('workstreamId') } }, async (request) =>
    workstreamManagers.listForWorkstream(request.params.workstreamId),
  );

  app.post(
    '/',
    {
      onRequest: guard,
      schema: { params: uuidParams('workstreamId'), body: obj({ userId: uuid }, ['userId']) },
    },
    async (request) => {
      request.auditEntity = 'workstream_managers';
      const row = await workstreamManagers.assign(request.params.workstreamId, request.body.userId);
      request.auditEntityId = row.id;
      return row;
    },
  );

  app.delete(
    '/:userId',
    { onRequest: guard, schema: { params: uuidParams('workstreamId', 'userId') } },
    async (request) => {
      request.auditEntity = 'workstream_managers';
      return workstreamManagers.unassign(request.params.workstreamId, request.params.userId);
    },
  );
}

/** "Which workstreams am I scoped to?" — any authenticated user may read their own assignments. */
async function myWorkstreamsRoutes(app) {
  app.get('/', { onRequest: [app.authenticate] }, async (request) =>
    app.services.workstreamManagers.listForUser(request.user.id),
  );
}

module.exports = { workstreamManagersRoutes, myWorkstreamsRoutes };
