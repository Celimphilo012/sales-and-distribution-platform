'use strict';

const { AttributeDataType } = require('@prisma/client');
const { obj, nonEmpty, str, bool, opt, enumOf, boolQuery, uuidParams } = require('../../core/schema');

const createBody = obj(
  { name: nonEmpty(), code: nonEmpty(), dataType: opt(enumOf(AttributeDataType)), unit: opt(str()) },
  ['name', 'code'],
);
const updateBody = obj({
  name: opt(nonEmpty()),
  code: opt(nonEmpty()),
  dataType: opt(enumOf(AttributeDataType)),
  unit: opt(str()),
  isActive: opt(bool),
});

// The admin-managed type catalog behind product attributes: catalogue.view to read, products.manage
// to create/edit/deactivate. Adding a type ("Country of Origin") is how the attribute model stays
// extensible without a code change.
async function attributeTypesRoutes(app) {
  const { attributeTypes } = app.services;
  const view = [app.authenticate, app.requirePermissions('catalogue.view')];
  const manage = [app.authenticate, app.requirePermissions('products.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: view, schema: { querystring: obj({ includeInactive: boolQuery }) } }, async (request) =>
    attributeTypes.findAll(request.query),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) => attributeTypes.findOne(request.params.id));

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    attributeTypes.create(request.body),
  );

  app.patch('/:id', { onRequest: manage, schema: { ...idParams, body: updateBody } }, async (request) => {
    request.auditOldValue = await attributeTypes.getExisting(request.params.id);
    return attributeTypes.update(request.params.id, request.body);
  });

  app.delete('/:id', { onRequest: manage, schema: idParams }, async (request) => {
    request.auditOldValue = await attributeTypes.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return attributeTypes.remove(request.params.id);
  });
}

module.exports = attributeTypesRoutes;
