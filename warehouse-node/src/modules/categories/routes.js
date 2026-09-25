'use strict';

const { obj, nonEmpty, bool, uuid, opt, boolQuery, uuidParams } = require('../../core/schema');

const listQuery = obj({ includeInactive: boolQuery, parentId: uuid, workstreamId: uuid });
const createBody = obj({ name: nonEmpty(), parentId: opt(uuid), workstreamId: uuid }, ['name', 'workstreamId']);
const updateBody = obj({
  name: opt(nonEmpty()),
  parentId: opt(uuid), // null moves the category to the root
  isActive: opt(bool),
  workstreamId: opt(uuid),
});

async function categoriesRoutes(app) {
  const { categories } = app.services;
  const view = [app.authenticate, app.requirePermissions('catalogue.view')];
  const manage = [app.authenticate, app.requirePermissions('products.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) =>
    categories.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) =>
    categories.findOne(request.params.id, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    categories.create(request.body, request.user.id),
  );

  app.patch('/:id', { onRequest: manage, schema: { ...idParams, body: updateBody } }, async (request) => {
    request.auditOldValue = await categories.getExisting(request.params.id);
    return categories.update(request.params.id, request.body, request.user.id);
  });

  app.delete('/:id', { onRequest: manage, schema: idParams }, async (request) => {
    request.auditOldValue = await categories.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return categories.remove(request.params.id, request.user.id);
  });
}

module.exports = categoriesRoutes;
