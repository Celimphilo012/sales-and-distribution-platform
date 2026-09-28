'use strict';

const { obj, uuid } = require('../../core/schema');

// Read-only; never cached — it must show an order the moment it is reserved, and drop it once dispatched.
function packingRoutes(app) {
  app.get(
    '/',
    {
      onRequest: [app.authenticate, app.requirePermissions('packing.view')],
      schema: { querystring: obj({ workstreamId: uuid }) },
    },
    async (request) => app.services.packing.openOrders(request.user.id, request.query),
  );
}

module.exports = packingRoutes;
