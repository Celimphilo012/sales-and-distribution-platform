'use strict';

const { StockCountStatus } = require('../../core/enums');
const { obj, num, uuid, opt, arrayOf, enumOf, uuidParams } = require('../../core/schema');

const listQuery = obj({ status: enumOf(StockCountStatus), locationId: uuid });

const createBody = obj(
  {
    locationId: uuid,
    // Omit to snapshot every product that currently has a balance row at this location.
    productIds: opt(arrayOf(uuid, { uniqueItems: true, minItems: 1 })),
  },
  ['locationId'],
);

const submitBody = obj(
  {
    items: arrayOf(
      obj({ productId: uuid, countedQty: num({ multipleOf: 0.001, minimum: 0 }) }, ['productId', 'countedQty']),
      { minItems: 1 },
    ),
  },
  ['items'],
);

// Mounted at /inventory/counts. A count records variance only; nonzero variances become PENDING
// adjustments (rule 2: the count itself never writes the ledger).
function stockCountsRoutes(app) {
  const { stockCounts, otp } = app.services;
  const guard = [app.authenticate, app.requirePermissions('inventory.count')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: guard, schema: { querystring: listQuery } }, async (request) =>
    stockCounts.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: guard, schema: idParams }, async (request) =>
    stockCounts.getAccessible(request.params.id, request.user.id),
  );

  app.post('/', { onRequest: guard, schema: { body: createBody } }, async (request) => {
    const count = await stockCounts.create(request.body, request.user.id);
    request.auditEntity = 'stock_counts';
    request.auditEntityId = count.id;
    return count;
  });

  // Submitting is confirmed with a one-time code (catalog/otp-actions.js).
  app.patch(
    '/:id',
    { onRequest: guard, preHandler: [otp.requireOtp('stock_count.submit')], schema: { ...idParams, body: submitBody } },
    async (request) => {
      request.auditEntity = 'stock_counts';
      request.auditOldValue = await stockCounts.getExisting(request.params.id);
      request.auditAction = 'SUBMIT';
      return stockCounts.submit(request.params.id, request.body, request.user.id);
    },
  );
}

module.exports = stockCountsRoutes;
