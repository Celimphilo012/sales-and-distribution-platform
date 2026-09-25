'use strict';

const { obj, nonEmpty, str, num, uuid, dateString, opt } = require('../../core/schema');

// Up to 3 decimal places, strictly positive.
const quantity = num({ multipleOf: 0.001, exclusiveMinimum: 0 });

const body = obj(
  {
    supplier: nonEmpty(),
    productId: uuid,
    quantity,
    toLocationId: uuid,
    receivedDate: opt(dateString),
    reference: opt(str()),
    notes: opt(str()),
  },
  ['supplier', 'productId', 'quantity', 'toLocationId'],
);

// Mounted at /inventory/receiving
async function receivingRoutes(app) {
  const { receiving } = app.services;

  app.post(
    '/',
    { onRequest: [app.authenticate, app.requirePermissions('inventory.receive')], schema: { body } },
    async (request) => {
      const transaction = await receiving.receive(request.body, request.user.id);
      // This route creates an inventory_transactions row (there is no "receiving" table) — point the
      // audit log at what was actually written, not the URL's first segment.
      request.auditEntity = 'inventory_transactions';
      request.auditEntityId = transaction.id;
      return transaction;
    },
  );
}

module.exports = receivingRoutes;
