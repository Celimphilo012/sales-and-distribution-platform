'use strict';

const { badRequest, conflict, notFound } = require('../core/errors');
const { cols, nest, Where } = require('../core/models');
const { ExpenseCategory, ExpenseStatus } = require('../core/enums');
const { obj, str, num, opt, enumOf, dateString, uuidParams } = require('../core/schema');

const round2 = (n) => Math.round(n * 100) / 100;

/** Every report/statement/margin query in this module is scoped to orders that represent a real
 * sale — a DRAFT was never submitted and a REJECTED/CANCELLED order was never fulfilled. Matches
 * the exact exclusion `getPaymentsReport`'s outstanding-orders query already uses. */
const LIVE_ORDER_STATUS = "o.status NOT IN ('DRAFT', 'REJECTED', 'CANCELLED')";

const EXPENSE_SELECT = `
  SELECT ${cols('expense', 'e')},
         ${cols('user', 'ru', ['id', 'fullName'], 'recordedByUser.')},
         ${cols('user', 'vu', ['id', 'fullName'], 'voidedByUser.')}
    FROM expenses e
    JOIN users ru ON ru.id = e.recorded_by
    LEFT JOIN users vu ON vu.id = e.voided_by`;

/**
 * Finances: a dashboard (cash collected, AR aging, revenue trend), per-customer statements, expense
 * tracking (modelled directly on `payments` — money out instead of money in, same
 * void-not-edit-or-delete discipline), and margin reporting. Separate from `reports.js` (the
 * existing ops Dashboard/Reports surface) since this is a distinct audience/permission boundary.
 */
function createFinancesService({ db, reports, customers, models }) {
  /** Orders in the period (AR aging, revenue trend) — one WHERE builder shared by both queries below. */
  function liveOrdersWhere(query) {
    const where = new Where().raw(LIVE_ORDER_STATUS);
    if (query.from) where.raw('o.order_date >= ?', new Date(query.from));
    if (query.to) where.raw('o.order_date <= ?', new Date(query.to));
    return where;
  }

  /** Cash collected (reused from reports.js), AR aging buckets, and a weekly revenue trend — every
   * number a SQL aggregate, never a full-table fetch summed in JS. */
  async function getSummary(query = {}) {
    const paymentsReport = await reports.getPaymentsReport(query);
    const where = liveOrdersWhere(query);

    const [agingRows, trendRows] = await Promise.all([
      db.query(
        `SELECT
            CASE
              WHEN DATEDIFF(CURDATE(), o.order_date) <= 30 THEN '0-30'
              WHEN DATEDIFF(CURDATE(), o.order_date) <= 60 THEN '31-60'
              WHEN DATEDIFF(CURDATE(), o.order_date) <= 90 THEN '61-90'
              ELSE '90+'
            END AS bucket,
            COUNT(*) AS n, SUM(o.total - COALESCE(paid.amount, 0)) AS amount
           FROM orders o
           LEFT JOIN (SELECT order_id, SUM(amount) AS amount FROM payments WHERE status = 'RECORDED' GROUP BY order_id) paid
                  ON paid.order_id = o.id
           ${where.sql} AND o.total - COALESCE(paid.amount, 0) > 0.005
          GROUP BY bucket`,
        where.params,
      ),
      // YEARWEEK mode 3: ISO-8601 weeks (Monday start) — a reasonable trend granularity without a
      // calendar table; weekStart approximates the week's Monday from whichever rows fall in it.
      db.query(
        `SELECT YEARWEEK(o.order_date, 3) AS week, MIN(DATE(o.order_date)) AS weekStart, SUM(o.total) AS revenue
           FROM orders o ${where.sql}
          GROUP BY week
          ORDER BY week ASC`,
        where.params,
      ),
    ]);

    const bucketOrder = ['0-30', '31-60', '61-90', '90+'];
    const aging = bucketOrder.map((bucket) => {
      const row = agingRows.find((r) => r.bucket === bucket);
      return { bucket, count: Number(row?.n ?? 0), amount: round2(Number(row?.amount ?? 0)) };
    });

    return {
      filters: query,
      collected: paymentsReport.collected,
      outstanding: paymentsReport.outstanding,
      aging,
      revenueTrend: trendRows.map((r) => ({ weekStart: r.weekStart, revenue: round2(Number(r.revenue)) })),
    };
  }

  /** One customer's orders + payments merged into a single dated ledger with a running balance. */
  async function getStatement(customerId, query = {}) {
    const customer = await customers.getExisting(customerId);

    const orderWhere = new Where().eq('o.customer_id', customerId).raw(LIVE_ORDER_STATUS);
    if (query.from) orderWhere.raw('o.order_date >= ?', new Date(query.from));
    if (query.to) orderWhere.raw('o.order_date <= ?', new Date(query.to));

    const paymentWhere = new Where().eq('o.customer_id', customerId);
    if (query.from) paymentWhere.raw('p.paid_at >= ?', new Date(query.from));
    if (query.to) paymentWhere.raw('p.paid_at <= ?', new Date(query.to));

    const [orderRows, paymentRows] = await Promise.all([
      db.query(
        `SELECT o.id, o.order_number AS orderNumber, o.order_date AS occurredAt, o.total AS amount
           FROM orders o ${orderWhere.sql}
          ORDER BY o.order_date ASC`,
        orderWhere.params,
      ),
      db.query(
        `SELECT p.id, p.order_id AS orderId, o.order_number AS orderNumber, p.paid_at AS occurredAt,
                p.amount, p.method, p.status
           FROM payments p JOIN orders o ON o.id = p.order_id ${paymentWhere.sql}
          ORDER BY p.paid_at ASC`,
        paymentWhere.params,
      ),
    ]);

    const entries = [
      ...orderRows.map((o) => ({
        type: 'ORDER',
        occurredAt: o.occurredAt,
        orderId: o.id,
        orderNumber: o.orderNumber,
        amount: round2(Number(o.amount)),
        effect: round2(Number(o.amount)),
      })),
      // A VOIDED payment still appears (never deleted, same ethos as the payment itself) but has no
      // effect on the running balance — settle() already excludes it from amountPaid.
      ...paymentRows.map((p) => ({
        type: 'PAYMENT',
        occurredAt: p.occurredAt,
        orderId: p.orderId,
        orderNumber: p.orderNumber,
        amount: round2(Number(p.amount)),
        method: p.method,
        status: p.status,
        effect: p.status === 'RECORDED' ? -round2(Number(p.amount)) : 0,
      })),
    ].sort((a, b) => new Date(a.occurredAt) - new Date(b.occurredAt));

    let running = 0;
    for (const entry of entries) {
      running = round2(running + entry.effect);
      entry.balance = running;
    }

    const bought = round2(orderRows.reduce((sum, o) => sum + Number(o.amount), 0));
    const paid = round2(paymentRows.filter((p) => p.status === 'RECORDED').reduce((sum, p) => sum + Number(p.amount), 0));

    return {
      customer: { id: customer.id, name: customer.name },
      filters: query,
      bought,
      paid,
      balanceDue: round2(bought - paid),
      entries,
    };
  }

  /** Margin per product — ONLY over lines with a known unit_cost (never treats an unknown cost as
   * 0, same rule warehouse-node's inventory valuation already enforces, for the same reason). */
  async function getMargin(query = {}) {
    const allWhere = liveOrdersWhere(query);
    const knownWhere = liveOrdersWhere(query).raw('i.unit_cost IS NOT NULL');

    const [totalRevenueRow, knownRow, productRows] = await Promise.all([
      db.one(
        `SELECT COALESCE(SUM(i.unit_price * i.quantity_fulfilled), 0) AS revenue
           FROM order_items i JOIN orders o ON o.id = i.order_id ${allWhere.sql}`,
        allWhere.params,
      ),
      db.one(
        `SELECT COALESCE(SUM(i.unit_price * i.quantity_fulfilled), 0) AS revenue,
                COALESCE(SUM((i.unit_price - i.unit_cost) * i.quantity_fulfilled), 0) AS margin
           FROM order_items i JOIN orders o ON o.id = i.order_id ${knownWhere.sql}`,
        knownWhere.params,
      ),
      db.query(
        `SELECT i.product_id AS productId, MAX(i.product_name) AS productName,
                SUM(i.quantity_fulfilled) AS quantity,
                SUM(i.unit_price * i.quantity_fulfilled) AS revenue,
                SUM((i.unit_price - i.unit_cost) * i.quantity_fulfilled) AS margin
           FROM order_items i JOIN orders o ON o.id = i.order_id ${knownWhere.sql}
          GROUP BY i.product_id
          ORDER BY margin DESC`,
        knownWhere.params,
      ),
    ]);

    const totalRevenue = round2(Number(totalRevenueRow.revenue));
    const knownCostRevenue = round2(Number(knownRow.revenue));
    return {
      filters: query,
      totalRevenue,
      knownCostRevenue,
      // What fraction of revenue in the period has a known margin — a costing gap stays visible
      // instead of being silently hidden by treating it as zero.
      knownCostRevenuePct: totalRevenue > 0 ? round2((knownCostRevenue / totalRevenue) * 100) : 0,
      margin: round2(Number(knownRow.margin)),
      products: productRows.map((p) => ({
        productId: p.productId,
        productName: p.productName,
        quantity: Number(p.quantity),
        revenue: round2(Number(p.revenue)),
        margin: round2(Number(p.margin)),
      })),
    };
  }

  async function getExistingExpense(id, executor) {
    const row = await db.one(`${EXPENSE_SELECT} WHERE e.id = ?`, [id], executor);
    if (!row) throw notFound(`Expense ${id} not found`);
    return nest(row);
  }

  async function findAllExpenses(query = {}) {
    const where = new Where().eq('e.category', query.category).eq('e.status', query.status);
    if (query.from) where.raw('e.incurred_at >= ?', query.from);
    if (query.to) where.raw('e.incurred_at <= ?', query.to);
    const rows = await db.query(`${EXPENSE_SELECT} ${where.sql} ORDER BY e.incurred_at DESC, e.created_at DESC`, where.params);
    return rows.map(nest);
  }

  async function recordExpense(dto, recordedBy) {
    const expense = await models.insert('expense', {
      category: dto.category,
      amount: round2(dto.amount),
      description: dto.description?.trim() || null,
      incurredAt: new Date(dto.incurredAt),
      recordedBy,
    });
    return getExistingExpense(expense.id);
  }

  /** Mirrors payments.js's voidPayment exactly: never edited/deleted, re-checked under a row lock
   * so two concurrent voids of the same expense cannot both succeed. */
  async function voidExpense(id, reason, voidedBy) {
    if (!reason?.trim()) throw badRequest('Give a reason for voiding this expense');
    await db.transaction(async (tx) => {
      const current = await db.one('SELECT status FROM expenses WHERE id = ? FOR UPDATE', [id], tx);
      if (!current) throw notFound(`Expense ${id} not found`);
      if (current.status === 'VOIDED') throw conflict('This expense has already been voided');
      await models.update('expense', id, { status: 'VOIDED', voidedBy, voidedAt: new Date(), voidReason: reason.trim() }, 'Expense', tx);
    });
    return getExistingExpense(id);
  }

  return { getSummary, getStatement, getMargin, getExistingExpense, findAllExpenses, recordExpense, voidExpense };
}

// ---- Routes ------------------------------------------------------------------------------------

const money = num({ exclusiveMinimum: 0, maximum: 9_999_999_999.99, multipleOf: 0.01 });
const periodQuery = obj({ from: dateString, to: dateString });

function financesRoutes(app) {
  const { finances, otp } = app.services;
  const { authenticate, requirePermissions } = app;
  const view = [authenticate, requirePermissions('finances.view')];

  app.get('/summary', { onRequest: view, schema: { querystring: periodQuery } }, async (request) => finances.getSummary(request.query));

  app.get(
    '/statements/:customerId',
    { onRequest: view, schema: { params: uuidParams('customerId'), querystring: periodQuery } },
    async (request) => finances.getStatement(request.params.customerId, request.query),
  );

  app.get('/margin', { onRequest: view, schema: { querystring: periodQuery } }, async (request) => finances.getMargin(request.query));

  app.get(
    '/expenses',
    {
      onRequest: view,
      schema: { querystring: obj({ category: enumOf(ExpenseCategory), status: enumOf(ExpenseStatus), from: dateString, to: dateString }) },
    },
    async (request) => finances.findAllExpenses(request.query),
  );

  app.post(
    '/expenses',
    {
      onRequest: [authenticate, requirePermissions('finances.expenses.record')],
      schema: {
        body: obj(
          { category: enumOf(ExpenseCategory), amount: money, description: opt(str({ maxLength: 500 })), incurredAt: dateString },
          ['category', 'amount', 'incurredAt'],
        ),
      },
    },
    async (request) => {
      const expense = await finances.recordExpense(request.body, request.user.id);
      request.auditEntityId = expense.id;
      request.auditAction = 'RECORD_EXPENSE';
      return expense;
    },
  );

  app.post(
    '/expenses/:id/void',
    {
      onRequest: [authenticate, requirePermissions('finances.expenses.void')],
      preHandler: [otp.requireOtp('expense.void')],
      schema: { params: uuidParams('id'), body: obj({ reason: str({ minLength: 1, maxLength: 500 }) }, ['reason']) },
    },
    async (request, res) => {
      request.auditOldValue = await finances.getExistingExpense(request.params.id);
      request.auditAction = 'VOID_EXPENSE';
      res.status(200);
      return finances.voidExpense(request.params.id, request.body.reason, request.user.id);
    },
  );
}

module.exports = { createFinancesService, financesRoutes };
