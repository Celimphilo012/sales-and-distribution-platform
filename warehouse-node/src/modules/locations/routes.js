'use strict';

const { obj, nonEmpty, str, int, bool, uuid, opt, boolQuery, uuidParams } = require('../../core/schema');

const listQuery = obj({ warehouseId: uuid, parentId: uuid, rootOnly: boolQuery, includeInactive: boolQuery });
const includeInactiveQuery = obj({ includeInactive: boolQuery });

const createBody = obj(
  {
    warehouseId: opt(uuid),
    parentId: opt(uuid),
    name: nonEmpty(),
    code: nonEmpty(),
    locationType: nonEmpty(),
    description: opt(str()),
    // How many units this location holds when full (storage slots) — drives the fill/utilisation bars.
    capacity: opt(int({ minimum: 0, maximum: 100000000 })),
  },
  ['name', 'code', 'locationType'],
);

// Same shape as create minus warehouseId/parentId (derived from the route).
const childBody = obj(
  {
    name: nonEmpty(),
    code: nonEmpty(),
    locationType: nonEmpty(),
    description: opt(str()),
    capacity: opt(int({ minimum: 0, maximum: 100000000 })),
  },
  ['name', 'code', 'locationType'],
);

const levelsBody = obj(
  {
    count: int({ minimum: 1 }),
    locationType: opt(nonEmpty()),
    namePrefix: opt(nonEmpty()),
    codePrefix: opt(nonEmpty()),
    startIndex: opt(int({ minimum: 1 })),
    capacity: opt(int({ minimum: 0, maximum: 100000000 })),
  },
  ['count'],
);

// The key must be present; null is a meaningful value (move to the root of the warehouse).
const moveBody = obj({ parentId: { type: ['string', 'null'], format: 'uuid' } }, ['parentId']);

const updateBody = obj({
  name: opt(nonEmpty()),
  code: opt(nonEmpty()),
  locationType: opt(nonEmpty()),
  description: opt(str()),
  capacity: opt(int({ minimum: 0, maximum: 100000000 })),
  isActive: opt(bool),
});

function locationsRoutes(app) {
  const { locations, otp } = app.services;
  const view = [app.authenticate, app.requirePermissions('warehouse.structure.view')];
  const manage = [app.authenticate, app.requirePermissions('warehouse.structure.manage')];
  const idParams = { params: uuidParams('id') };
  const deactivateOtp = otp.requireOtp('location.deactivate', { when: (req) => req.body.isActive === false });

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) =>
    locations.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) =>
    locations.findOne(request.params.id, request.user.id),
  );

  app.get(
    '/:id/children',
    { onRequest: view, schema: { ...idParams, querystring: includeInactiveQuery } },
    async (request) =>
      locations.children(request.params.id, request.query.includeInactive === true, request.user.id),
  );

  app.get(
    '/:id/subtree',
    { onRequest: view, schema: { ...idParams, querystring: includeInactiveQuery } },
    async (request) =>
      locations.subtree(request.params.id, request.query.includeInactive === true, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    locations.create(request.body, request.user.id),
  );

  app.post('/:id/children', { onRequest: manage, schema: { ...idParams, body: childBody } }, async (request) => {
    const child = await locations.addChild(request.params.id, request.body, request.user.id);
    request.auditEntityId = child.id;
    return child;
  });

  app.post('/:id/levels', { onRequest: manage, schema: { ...idParams, body: levelsBody } }, async (request) => {
    request.auditAction = 'GENERATE_LEVELS';
    return locations.generateLevels(request.params.id, request.body, request.user.id);
  });

  app.post('/:id/move', { onRequest: manage, schema: { ...idParams, body: moveBody } }, async (request) => {
    request.auditOldValue = await locations.getExisting(request.params.id);
    request.auditAction = 'MOVE';
    return locations.move(request.params.id, request.body, request.user.id);
  });

  app.patch(
    '/:id',
    { onRequest: manage, preHandler: [deactivateOtp], schema: { ...idParams, body: updateBody } },
    async (request) => {
      request.auditOldValue = await locations.getExisting(request.params.id);
      return locations.update(request.params.id, request.body, request.user.id);
    },
  );

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('location.deactivate')], schema: idParams },
    async (request) => {
      request.auditOldValue = await locations.getExisting(request.params.id);
      request.auditAction = 'DEACTIVATE';
      return locations.remove(request.params.id, request.user.id);
    },
  );
}

module.exports = locationsRoutes;
