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

  /**
   * Money in (RECORDED payments in the period, by method), money voided, and what customers still
   * owe on live orders (every order that can take payment: not DRAFT / REJECTED / CANCELLED). All
   * aggregated in SQL.
   */
  async function getPaymentsReport(query = {}) {
    const paymentsIn = (status) => {
      const where = new Where().eq('p.status', status);
      if (query.from) where.raw('p.paid_at >= ?', new Date(query.from));
      if (query.to) where.raw('p.paid_at <= ?', new Date(query.to));
      return where;
    };
    const recorded = paymentsIn('RECORDED');
    const voided = paymentsIn('VOIDED');

    const [byMethod, voidRow, outstandingRows] = await Promise.all([
      db.query(
        `SELECT p.method, COUNT(*) AS n, SUM(p.amount) AS amount FROM payments p ${recorded.sql} GROUP BY p.method ORDER BY p.method`,
        recorded.params,
      ),
      db.one(`SELECT COUNT(*) AS n, COALESCE(SUM(p.amount), 0) AS amount FROM payments p ${voided.sql}`, voided.params),
      db.query(
        `SELECT o.id, o.order_number AS orderNumber, o.status, o.payment_status AS paymentStatus, o.order_date AS orderDate,
                o.total, c.id AS \`customer.id\`, c.name AS \`customer.name\`,
                COALESCE(paid.amount, 0) AS amountPaid, o.total - COALESCE(paid.amount, 0) AS balanceDue
           FROM orders o
           JOIN customers c ON c.id = o.customer_id
           LEFT JOIN (SELECT order_id, SUM(amount) AS amount FROM payments WHERE status = 'RECORDED' GROUP BY order_id) paid
                  ON paid.order_id = o.id
          WHERE o.status NOT IN ('DRAFT', 'REJECTED', 'CANCELLED') AND o.total - COALESCE(paid.amount, 0) > 0.005
          ORDER BY balanceDue DESC, o.order_date ASC`,
      ),
    ]);

    const methods = byMethod.map((m) => ({ method: m.method, count: Number(m.n), amount: round2(Number(m.amount)) }));
    return {
      filters: query,
      collected: {
        count: methods.reduce((n, m) => n + m.count, 0),
        amount: round2(methods.reduce((sum, m) => sum + m.amount, 0)),
        byMethod: methods,
      },
      voided: { count: Number(voidRow.n), amount: round2(Number(voidRow.amount)) },
      outstanding: {
        orderCount: outstandingRows.length,
        amount: round2(outstandingRows.reduce((sum, o) => sum + Number(o.balanceDue), 0)),
        orders: outstandingRows.map((o) => {
          const row = nest(o);
          return { ...row, amountPaid: round2(Number(row.amountPaid)), balanceDue: round2(Number(row.balanceDue)) };
        }),
      },
    };
  }

  /** One payload for the manager dashboard: order counts and value, money in, money owed, latest orders. */
  async function getDashboard() {
    const [overall, today, thisWeek, paidToday, paidThisWeek, payments, recentOrders] = await Promise.all([
      getOrdersReport(),
      getOrdersReport({ from: startOfToday().toISOString() }),
      getOrdersReport({ from: startOfThisWeek().toISOString() }),
      getPaymentsReport({ from: startOfToday().toISOString() }),
      getPaymentsReport({ from: startOfThisWeek().toISOString() }),
      getPaymentsReport(),
      db.query(
        `SELECT ${cols('order', 'o', ['id', 'orderNumber', 'status', 'paymentStatus', 'orderDate', 'total'])},
                ${cols('customer', 'c', ['id', 'name'], 'customer.')}
           FROM orders o JOIN customers c ON c.id = o.customer_id
          ORDER BY o.created_at DESC LIMIT 8`,
      ),
    ]);
    const awaiting = overall.byStatus.find((s) => s.status === 'PENDING_APPROVAL');
    return {
      ordersByStatus: overall.byStatus,
      today: { orderCount: today.count, totalValue: today.totalValue, collected: paidToday.collected.amount },
      thisWeek: { orderCount: thisWeek.count, totalValue: thisWeek.totalValue, collected: paidThisWeek.collected.amount },
      awaitingApproval: awaiting?.count ?? 0,
      outstanding: { orderCount: payments.outstanding.orderCount, amount: payments.outstanding.amount },
      recentOrders: recentOrders.map(nest),
    };
  }

  return { getOrdersReport, getPaymentsReport, getDashboard };
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

  app.get(
    '/payments',
    {
      onRequest: [app.authenticate, app.requirePermissions('reports.view')],
      schema: { querystring: obj({ from: dateString, to: dateString }) },
    },
    async (request) => app.services.reports.getPaymentsReport(request.query),
  );
}

function dashboardRoutes(app) {
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('reports.view')] }, async () =>
    app.services.reports.getDashboard(),
  );
}

module.exports = { createReportsService, reportsRoutes, dashboardRoutes };
