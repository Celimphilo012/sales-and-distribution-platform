'use strict';

const { cols, nest, Where } = require('../core/models');
const { OrderStatus } = require('../core/enums');
const { obj, uuid, enumOf, dateString } = require('../core/schema');

const round2 = (n) => Math.round(n * 100) / 100;

/**
 * Order-side reporting (read-only). count / totalValue / byStatus all derive from orders.status and
 * orders.total, aggregated in SQL — never recomputed from line prices.
 */
function createReportsService({ db }) {
  async function getOrdersReport(query = {}) {
    const where = new Where().eq('o.status', query.status).eq('o.customer_id', query.customerId);
    if (query.from) where.raw('o.order_date >= ?', new Date(query.from));
    if (query.to) where.raw('o.order_date <= ?', new Date(query.to));

    const [orders, byStatus] = await Promise.all([
      db.query(
        `SELECT ${cols('order', 'o', ['id', 'orderNumber', 'status', 'paymentStatus', 'customerId', 'consultantId', 'orderDate', 'total'])},
                ${cols('customer', 'c', ['id', 'name'], 'customer.')}
           FROM orders o JOIN customers c ON c.id = o.customer_id
           ${where.sql}
          ORDER BY o.order_date DESC`,
        where.params,
      ),
      db.query(
        `SELECT o.status, COUNT(*) AS n, SUM(o.total) AS totalValue FROM orders o ${where.sql} GROUP BY o.status ORDER BY o.status`,
        where.params,
      ),
    ]);

    return {
      filters: query,
      count: orders.length,
      totalValue: round2(orders.reduce((sum, o) => sum + Number(o.total), 0)),
      byStatus: byStatus.map((s) => ({ status: s.status, count: Number(s.n), totalValue: round2(Number(s.totalValue ?? 0)) })),
      orders: orders.map(nest),
    };
  }

  const startOfToday = () => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  };

  /** Monday 00:00 of the current week (server-local time). */
  const startOfThisWeek = () => {
    const d = startOfToday();
    const day = d.getDay(); // 0 = Sunday
    d.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
    return d;
  };

  /** One payload for the manager dashboard cards — order side only. */
  async function getDashboard() {
    const [overall, today, thisWeek] = await Promise.all([
      getOrdersReport(),
      getOrdersReport({ from: startOfToday().toISOString() }),
      getOrdersReport({ from: startOfThisWeek().toISOString() }),
    ]);
    return {
      ordersByStatus: overall.byStatus,
      today: { orderCount: today.count, totalValue: today.totalValue },
      thisWeek: { orderCount: thisWeek.count, totalValue: thisWeek.totalValue },
    };
  }

  return { getOrdersReport, getDashboard };
}

function reportsRoutes(app) {
  app.get(
    '/orders',
    {
      onRequest: [app.authenticate, app.requirePermissions('reports.view')],
      schema: { querystring: obj({ status: enumOf(OrderStatus), customerId: uuid, from: dateString, to: dateString }) },
    },
    async (request) => app.services.reports.getOrdersReport(request.query),
  );
}

function dashboardRoutes(app) {
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('reports.view')] }, async () =>
    app.services.reports.getDashboard(),
  );
}

module.exports = { createReportsService, reportsRoutes, dashboardRoutes };
