'use strict';

const { obj, int } = require('../../core/schema');

const periodQuery = obj({ days: int({ minimum: 1, maximum: 365 }) });

// Pure reads — none of these write an audit_logs row. Every figure is limited to the viewer's warehouses.
function reportsRoutes(app) {
  const { reports } = app.services;
  const guard = [app.authenticate, app.requirePermissions('reports.view')];

  app.get('/low-stock', { onRequest: guard }, async (request) => reports.getLowStock(request.user.id));
  app.get('/inventory-valuation', { onRequest: guard }, async (request) => reports.getInventoryValuation(request.user.id));
  app.get('/stock-movement-summary', { onRequest: guard, schema: { querystring: periodQuery } }, async (request) =>
    reports.getStockMovementSummary(request.query.days, request.user.id),
  );
  app.get('/adjustments-summary', { onRequest: guard, schema: { querystring: periodQuery } }, async (request) =>
    reports.getAdjustmentsSummary(request.query.days, request.user.id),
  );
}

function dashboardRoutes(app) {
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('reports.view')] }, async (request) =>
    app.services.reports.getDashboard(request.user.id),
  );
}

module.exports = { reportsRoutes, dashboardRoutes };
