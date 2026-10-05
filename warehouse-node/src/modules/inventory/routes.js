'use strict';

const { InventoryTransactionType, InventoryUnitStatus } = require('../../core/enums');
const { obj, uuid, dateString, enumOf, int, opt } = require('../../core/schema');

const balancesQuery = obj({ productId: uuid, locationId: uuid, warehouseId: uuid });
const transactionsQuery = obj({
  productId: uuid,
  locationId: uuid,
  type: enumOf(InventoryTransactionType),
  from: dateString,
  to: dateString,
  // Newest first; a limit keeps history screens (receipts, transfers) quick on a large ledger.
  limit: int({ minimum: 1, maximum: 5000 }),
});
const unitsQuery = obj(
  {
    productId: uuid,
    status: opt(enumOf(InventoryUnitStatus)),
    page: opt(int({ minimum: 1 })),
    pageSize: opt(int({ minimum: 1, maximum: 100 })),
  },
  ['productId'],
);

// Read-only views over the ledger — every write goes through InventoryService.applyTransaction.
// Deliberately not cached: these are the screens people check right after receiving/transferring stock.
function inventoryRoutes(app) {
  const { inventory } = app.services;
  const guard = [app.authenticate, app.requirePermissions('inventory.view')];

  app.get('/balances', { onRequest: guard, schema: { querystring: balancesQuery } }, async (request) =>
    inventory.findBalances(request.query, request.user.id),
  );

  app.get('/transactions', { onRequest: guard, schema: { querystring: transactionsQuery } }, async (request) =>
    inventory.findTransactions(request.query, request.user.id),
  );

  // One SERIAL product's units (its own code, status, current location), paginated.
  app.get('/units', { onRequest: guard, schema: { querystring: unitsQuery } }, async (request) =>
    inventory.findUnits(request.query, request.user.id),
  );
}

module.exports = inventoryRoutes;
