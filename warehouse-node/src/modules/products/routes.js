'use strict';

const { ProductStatus } = require('../../core/enums');
const { obj, nonEmpty, str, num, uuid, opt, arrayOf, enumOf, boolQuery, uuidParams } = require('../../core/schema');

// Money/quantity fields: at most 2 decimal places (handled by Ajv's multipleOf precision option).
const money = (extra = {}) => num({ multipleOf: 0.01, ...extra });

const attributeInput = obj(
  {
    attributeTypeId: uuid,
    value: { type: ['string', 'number'] },
  },
  ['attributeTypeId', 'value'],
);

const listQuery = obj({
  categoryId: uuid,
  workstreamId: uuid,
  status: enumOf(ProductStatus),
  includeInactive: boolQuery,
  search: str(),
  attribute: str(),
});

const createBody = obj(
  {
    sku: nonEmpty(),
    name: nonEmpty(),
    description: opt(str()),
    categoryId: uuid,
    sellingPrice: money({ exclusiveMinimum: 0 }),
    costPrice: opt(money({ minimum: 0 })),
    uom: nonEmpty(),
    minStockLevel: opt(money({ minimum: 0 })),
    attributes: opt(arrayOf(attributeInput)),
  },
  ['sku', 'name', 'categoryId', 'sellingPrice', 'uom'],
);

const updateBody = obj({
  // Editable: labels and scanners use the product's permanent id (WH:P:<id>), never the SKU.
  sku: opt(nonEmpty()),
  name: opt(nonEmpty()),
  description: opt(str()),
  categoryId: opt(uuid),
  sellingPrice: opt(money({ exclusiveMinimum: 0 })),
  costPrice: opt(money({ minimum: 0 })),
  uom: opt(nonEmpty()),
  minStockLevel: opt(money({ minimum: 0 })),
  status: opt(enumOf(ProductStatus)),
  attributes: opt(arrayOf(attributeInput)),
});

function productsRoutes(app) {
  const { products, otp } = app.services;
  const view = [app.authenticate, app.requirePermissions('catalogue.view')];
  const manage = [app.authenticate, app.requirePermissions('products.manage')];
  const idParams = { params: uuidParams('id') };
  const deactivateOtp = otp.requireOtp('product.deactivate', { when: (req) => req.body.status === 'INACTIVE' });

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) =>
    products.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) =>
    products.findOne(request.params.id, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    products.create(request.body, request.user.id),
  );

  app.patch(
    '/:id',
    { onRequest: manage, preHandler: [deactivateOtp], schema: { ...idParams, body: updateBody } },
    async (request) => {
      request.auditOldValue = await products.getExisting(request.params.id);
      return products.update(request.params.id, request.body, request.user.id);
    },
  );

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('product.deactivate')], schema: idParams },
    async (request) => {
      request.auditOldValue = await products.getExisting(request.params.id);
      request.auditAction = 'DEACTIVATE';
      return products.remove(request.params.id, request.user.id);
    },
  );
}

module.exports = productsRoutes;
