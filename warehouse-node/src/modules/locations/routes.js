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
  },
  ['name', 'code', 'locationType'],
);

// Same shape as create minus warehouseId/parentId (derived from the route).
const childBody = obj(
  { name: nonEmpty(), code: nonEmpty(), locationType: nonEmpty(), description: opt(str()) },
  ['name', 'code', 'locationType'],
);

const levelsBody = obj(
  {
    count: int({ minimum: 1 }),
    locationType: opt(nonEmpty()),
    namePrefix: opt(nonEmpty()),
    codePrefix: opt(nonEmpty()),
    startIndex: opt(int({ minimum: 1 })),
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
  isActive: opt(bool),
});

async function locationsRoutes(app) {
  const { locations } = app.services;
  const view = [app.authenticate, app.requirePermissions('warehouse.structure.view')];
  const manage = [app.authenticate, app.requirePermissions('warehouse.structure.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) =>
    locations.findAll(request.query),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) => locations.findOne(request.params.id));

  app.get(
    '/:id/children',
    { onRequest: view, schema: { ...idParams, querystring: includeInactiveQuery } },
    async (request) => locations.children(request.params.id, request.query.includeInactive === true),
  );

  app.get(
    '/:id/subtree',
    { onRequest: view, schema: { ...idParams, querystring: includeInactiveQuery } },
    async (request) => locations.subtree(request.params.id, request.query.includeInactive === true),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    locations.create(request.body),
  );

  app.post('/:id/children', { onRequest: manage, schema: { ...idParams, body: childBody } }, async (request) => {
    const child = await locations.addChild(request.params.id, request.body);
    request.auditEntityId = child.id;
    return child;
  });

  app.post('/:id/levels', { onRequest: manage, schema: { ...idParams, body: levelsBody } }, async (request) => {
    request.auditAction = 'GENERATE_LEVELS';
    return locations.generateLevels(request.params.id, request.body);
  });

  app.post('/:id/move', { onRequest: manage, schema: { ...idParams, body: moveBody } }, async (request) => {
    request.auditOldValue = await locations.getExisting(request.params.id);
    request.auditAction = 'MOVE';
    return locations.move(request.params.id, request.body);
  });

  app.patch('/:id', { onRequest: manage, schema: { ...idParams, body: updateBody } }, async (request) => {
    request.auditOldValue = await locations.getExisting(request.params.id);
    return locations.update(request.params.id, request.body);
  });

  app.delete('/:id', { onRequest: manage, schema: idParams }, async (request) => {
    request.auditOldValue = await locations.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return locations.remove(request.params.id);
  });
}

module.exports = locationsRoutes;
