'use strict';

const { obj, str, opt, arrayOf, uuidParams } = require('../../core/schema');

const createBody = obj({ name: str({ minLength: 2 }), description: opt(str()) }, ['name']);
const updateBody = obj({ name: opt(str({ minLength: 2 })), description: opt(str()) });
const assignBody = obj({ permissionIds: arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true }) }, [
  'permissionIds',
]);

async function rolesRoutes(app) {
  const { roles } = app.services;
  const guard = [app.authenticate, app.requirePermissions('roles.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: guard }, async () => roles.findAll());
  app.get('/:id', { onRequest: guard, schema: idParams }, async (request) => roles.findOne(request.params.id));
  app.post('/', { onRequest: guard, schema: { body: createBody } }, async (request) => roles.create(request.body));

  app.patch('/:id', { onRequest: guard, schema: { ...idParams, body: updateBody } }, async (request) => {
    request.auditOldValue = await roles.getExisting(request.params.id);
    return roles.update(request.params.id, request.body);
  });

  app.put('/:id/permissions', { onRequest: guard, schema: { ...idParams, body: assignBody } }, async (request) => {
    request.auditOldValue = await roles.getExisting(request.params.id);
    request.auditAction = 'ASSIGN_PERMISSIONS';
    return roles.assignPermissions(request.params.id, request.body);
  });

  app.delete('/:id', { onRequest: guard, schema: idParams }, async (request) => {
    request.auditOldValue = await roles.getExisting(request.params.id);
    return roles.remove(request.params.id);
  });
}

module.exports = rolesRoutes;
