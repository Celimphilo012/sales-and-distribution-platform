'use strict';

const { obj, str, num, uuid, opt } = require('../../core/schema');

const body = obj(
  {
    productId: uuid,
    quantity: num({ multipleOf: 0.001, exclusiveMinimum: 0 }),
    fromLocationId: uuid,
    toLocationId: uuid,
    reason: opt(str()),
    reference: opt(str()),
  },
  ['productId', 'quantity', 'fromLocationId', 'toLocationId'],
);

// Mounted at /inventory/transfers
function transfersRoutes(app) {
  const { transfers } = app.services;

  app.post(
    '/',
    { onRequest: [app.authenticate, app.requirePermissions('inventory.transfer')], schema: { body } },
    async (request) => {
      const transaction = await transfers.transfer(request.body, request.user.id);
      request.auditEntity = 'inventory_transactions';
      request.auditEntityId = transaction.id;
      return transaction;
    },
  );
}

module.exports = transfersRoutes;
