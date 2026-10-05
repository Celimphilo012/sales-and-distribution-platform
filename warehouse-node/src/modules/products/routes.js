'use strict';

const { ProductStatus, TrackingMode } = require('../../core/enums');
const { obj, nonEmpty, str, num, int, uuid, opt, arrayOf, enumOf, boolQuery, uuidParams } = require('../../core/schema');

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
    trackingMode: opt(enumOf(TrackingMode)),
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
  trackingMode: opt(enumOf(TrackingMode)),
  attributes: opt(arrayOf(attributeInput)),
});

const generateUnitsBody = obj({ count: int({ minimum: 1, maximum: 500 }) }, ['count']);

function productsRoutes(app) {
  const { products, otp, inventory } = app.services;
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

  // Pre-prints N unique unit labels for a SERIAL product, ahead of it physically arriving (see
  // inventory_units in db/schema.sql). Returns the new units' ids — the frontend builds one
  // QrLabel(payload: ScanCode.forUnit(id)) per id and prints them.
  app.post(
    '/:id/units/generate',
    { onRequest: manage, schema: { ...idParams, body: generateUnitsBody } },
    async (request) => {
      const unitIds = await inventory.generateUnits(request.params.id, request.body.count);
      request.auditEntity = 'inventory_units';
      request.auditBody = { productId: request.params.id, count: unitIds.length };
      return { unitIds };
    },
  );
}

module.exports = productsRoutes;
