'use strict';

const { obj, int } = require('../../core/schema');

const periodQuery = obj({ days: int({ minimum: 1, maximum: 365 }) });

// Pure reads — none of these write an audit_logs row.
async function reportsRoutes(app) {
  const { reports } = app.services;
  const guard = [app.authenticate, app.requirePermissions('reports.view')];

  app.get('/low-stock', { onRequest: guard }, async () => reports.getLowStock());
  app.get('/inventory-valuation', { onRequest: guard }, async () => reports.getInventoryValuation());
  app.get('/stock-movement-summary', { onRequest: guard, schema: { querystring: periodQuery } }, async (request) =>
    reports.getStockMovementSummary(request.query.days),
  );
  app.get('/adjustments-summary', { onRequest: guard, schema: { querystring: periodQuery } }, async (request) =>
    reports.getAdjustmentsSummary(request.query.days),
  );
}

async function dashboardRoutes(app) {
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('reports.view')] }, async () =>
    app.services.reports.getDashboard(),
  );
}

module.exports = { reportsRoutes, dashboardRoutes };
