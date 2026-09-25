'use strict';

const { obj, nonEmpty, bool, opt, boolQuery, uuidParams } = require('../../core/schema');

const createBody = obj({ name: nonEmpty(), code: nonEmpty() }, ['name', 'code']);
const updateBody = obj({ name: opt(nonEmpty()), code: opt(nonEmpty()), isActive: opt(bool) });

// Read routes need warehouse.structure.view; mutating routes need .manage (the seed grants ADMIN both).
async function warehousesRoutes(app) {
  const { warehouses } = app.services;
  const view = [app.authenticate, app.requirePermissions('warehouse.structure.view')];
  const manage = [app.authenticate, app.requirePermissions('warehouse.structure.manage')];
  const idParams = { params: uuidParams('id') };

  app.get(
    '/',
    { onRequest: view, schema: { querystring: obj({ includeInactive: boolQuery }) } },
    async (request) => warehouses.findAll(request.query),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) => warehouses.findOne(request.params.id));

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    warehouses.create(request.body),
  );

  app.patch('/:id', { onRequest: manage, schema: { ...idParams, body: updateBody } }, async (request) => {
    request.auditOldValue = await warehouses.getExisting(request.params.id);
    return warehouses.update(request.params.id, request.body);
  });

  app.delete('/:id', { onRequest: manage, schema: idParams }, async (request) => {
    request.auditAction = 'DEACTIVATE';
    return warehouses.remove(request.params.id);
  });
}

module.exports = warehousesRoutes;
