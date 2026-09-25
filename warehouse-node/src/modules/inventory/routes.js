'use strict';

const { InventoryTransactionType } = require('@prisma/client');
const { obj, uuid, dateString, enumOf } = require('../../core/schema');

const balancesQuery = obj({ productId: uuid, locationId: uuid, warehouseId: uuid });
const transactionsQuery = obj({
  productId: uuid,
  locationId: uuid,
  type: enumOf(InventoryTransactionType),
  from: dateString,
  to: dateString,
});

// Read-only views over the ledger — every write goes through InventoryService.applyTransaction.
// Deliberately not cached: these are the screens people check right after receiving/transferring stock.
async function inventoryRoutes(app) {
  const { inventory } = app.services;
  const guard = [app.authenticate, app.requirePermissions('inventory.view')];

  app.get('/balances', { onRequest: guard, schema: { querystring: balancesQuery } }, async (request) =>
    inventory.findBalances(request.query),
  );

  app.get('/transactions', { onRequest: guard, schema: { querystring: transactionsQuery } }, async (request) =>
    inventory.findTransactions(request.query),
  );
}

module.exports = inventoryRoutes;
