'use strict';

const { obj, nonEmpty, bool, opt, boolQuery, uuidParams } = require('../../core/schema');

const createBody = obj({ name: nonEmpty(), code: nonEmpty() }, ['name', 'code']);
const updateBody = obj({ name: opt(nonEmpty()), code: opt(nonEmpty()), isActive: opt(bool) });

// Read routes need warehouse.structure.view; mutating routes need .manage (the seed grants ADMIN both).
// Every route is further limited to the warehouses the user is assigned to (modules/access).
function warehousesRoutes(app) {
  const { warehouses, otp } = app.services;
  const view = [app.authenticate, app.requirePermissions('warehouse.structure.view')];
  const manage = [app.authenticate, app.requirePermissions('warehouse.structure.manage')];
  const idParams = { params: uuidParams('id') };
  const deactivateOtp = otp.requireOtp('warehouse.deactivate', { when: (req) => req.body.isActive === false });

  app.get(
    '/',
    { onRequest: view, schema: { querystring: obj({ includeInactive: boolQuery }) } },
    async (request) => warehouses.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) =>
    warehouses.findOne(request.params.id, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    warehouses.create(request.body, request.user.id),
  );

  app.patch(
    '/:id',
    { onRequest: manage, preHandler: [deactivateOtp], schema: { ...idParams, body: updateBody } },
    async (request) => {
      request.auditOldValue = await warehouses.getExisting(request.params.id);
      return warehouses.update(request.params.id, request.body, request.user.id);
    },
  );

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('warehouse.deactivate')], schema: idParams },
    async (request) => {
      request.auditAction = 'DEACTIVATE';
      return warehouses.remove(request.params.id, request.user.id);
    },
  );
}

module.exports = warehousesRoutes;
