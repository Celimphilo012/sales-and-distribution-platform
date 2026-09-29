'use strict';

const { badRequest, conflict, forbidden, notFound } = require('../core/errors');
const { cols, nest, Where } = require('../core/models');
const { PaymentMethod, PaymentRecordStatus } = require('../core/enums');
const { obj, str, num, uuid, opt, enumOf, dateString, uuidParams } = require('../core/schema');

const round2 = (n) => Math.round(n * 100) / 100;
/** Half a cent: money comparisons tolerate float noise, never a real cent. */
const EPSILON = 0.005;

/** Orders in these states take no payments — nothing was (or will be) sold. */
const NO_PAYMENT_STATUSES = ['DRAFT', 'REJECTED', 'CANCELLED'];
/** Methods whose payments must carry the provider's reference (MoMo id, bank ref, card slip). */
const REFERENCE_REQUIRED = ['MOBILE_MONEY', 'BANK_TRANSFER', 'CARD'];
/** A client clock a little ahead of ours is not "the future". */
const CLOCK_SKEW_MS = 5 * 60_000;

const PAYMENT_SELECT = `
  SELECT ${cols('payment', 'p')},
         ${cols('order', 'o', ['id', 'orderNumber'], 'order.')},
         ${cols('user', 'ru', ['id', 'fullName'], 'recordedByUser.')},
         ${cols('user', 'vu', ['id', 'fullName'], 'voidedByUser.')}
    FROM payments p
    JOIN orders o ON o.id = p.order_id
    JOIN users ru ON ru.id = p.recorded_by
    LEFT JOIN users vu ON vu.id = p.voided_by`;

/**
 * Payments against orders (rule 6: a separate lifecycle from order status — approving or
 * delivering an order says nothing about being paid).
 *
 *  - Many payments per order; each is CASH, MOBILE_MONEY, BANK_TRANSFER or CARD. Non-cash payments
 *    must carry the provider's reference.
 *  - The total of RECORDED payments may never exceed the order total (overpayment is refused).
 *  - A wrong payment is never edited or deleted: it is VOIDED (kept, with who/when/why), which is
 *    step-up protected by a one-time code at the route.
 *  - orders.payment_status (UNPAID / PARTIAL / PAID) is DERIVED from the recorded payments and
 *    rewritten in the SAME transaction as every payment write, under a row lock on the order, so two
 *    cashiers recording at once cannot overpay it together.
 */
function createPaymentsService({ db, models, orders, notifications }) {
  const loadPayments = async (where, executor) =>
    (await db.query(`${PAYMENT_SELECT} ${where.sql} ORDER BY p.paid_at ASC, p.created_at ASC`, where.params, executor)).map(nest);

  async function getExisting(id, executor) {
    const [payment] = await loadPayments(new Where().eq('p.id', id), executor);
    if (!payment) throw notFound(`Payment ${id} not found`);
    return payment;
  }

  /** Locks the order row for the rest of the transaction and returns what payment rules need. */
  async function lockOrder(orderId, tx) {
    const order = await db.one(
      'SELECT id, order_number AS orderNumber, status, total, consultant_id AS consultantId FROM orders WHERE id = ? FOR UPDATE',
      [orderId],
      tx,
    );
    if (!order) throw notFound(`Order ${orderId} not found`);
    return { ...order, total: Number(order.total) };
  }

  async function amountPaid(orderId, tx) {
    const row = await db.one(
      "SELECT COALESCE(SUM(amount), 0) AS paid FROM payments WHERE order_id = ? AND status = 'RECORDED'",
      [orderId],
      tx,
    );
    return round2(Number(row.paid));
  }

  const paymentStatusFor = (paid, total) => (paid <= EPSILON ? 'UNPAID' : paid + EPSILON >= total ? 'PAID' : 'PARTIAL');

  /** Rewrites orders.payment_status from the recorded payments; returns the order's money summary. */
  async function settle(order, tx) {
    const paid = await amountPaid(order.id, tx);
    const paymentStatus = paymentStatusFor(paid, order.total);
    await models.update('order', order.id, { paymentStatus }, 'Order', tx);
    return { orderId: order.id, total: order.total, amountPaid: paid, balanceDue: round2(order.total - paid), paymentStatus };
  }

  /** The money summary for one order (no lock — a read). */
  async function summary(orderId) {
    const order = await db.one('SELECT id, total, payment_status AS paymentStatus FROM orders WHERE id = ?', [orderId]);
    if (!order) throw notFound(`Order ${orderId} not found`);
    const paid = await amountPaid(orderId);
    const total = Number(order.total);
    return { orderId, total, amountPaid: paid, balanceDue: round2(total - paid), paymentStatus: order.paymentStatus };
  }

  async function listForOrder(orderId) {
    return { ...(await summary(orderId)), payments: await loadPayments(new Where().eq('p.order_id', orderId)) };
  }

  /** Every payment in a period (reports) — optional method / status filters. */
  function findAll(query = {}) {
    const where = new Where().eq('p.method', query.method).eq('p.status', query.status);
    if (query.from) where.raw('p.paid_at >= ?', new Date(query.from));
    if (query.to) where.raw('p.paid_at <= ?', new Date(query.to));
    return loadPayments(where);
  }

  async function record(dto, recordedBy) {
    const amount = round2(dto.amount);
    const reference = dto.reference?.trim() || null;
    if (REFERENCE_REQUIRED.includes(dto.method) && !reference) {
      throw badRequest('Enter the payment reference (MoMo transaction id, bank reference or card slip number)');
    }
    const paidAt = dto.paidAt ? new Date(dto.paidAt) : new Date();
    if (paidAt.getTime() > Date.now() + CLOCK_SKEW_MS) throw badRequest('paidAt cannot be in the future');

    const { paymentId, order, money } = await db.transaction(async (tx) => {
      const order = await lockOrder(dto.orderId, tx);
      if (NO_PAYMENT_STATUSES.includes(order.status)) {
        throw conflict(`Payments cannot be recorded on a ${order.status} order`);
      }
      const paid = await amountPaid(order.id, tx);
      const balance = round2(order.total - paid);
      if (amount > balance + EPSILON) {
        throw conflict(
          balance <= EPSILON
            ? `Order ${order.orderNumber} is already fully paid`
            : `This payment (E ${amount.toFixed(2)}) is more than the balance due (E ${balance.toFixed(2)}) — overpayment is not allowed`,
          { balanceDue: balance },
        );
      }
      const payment = await models.insert(
        'payment',
        { orderId: order.id, amount, method: dto.method, reference, notes: dto.notes?.trim() || null, paidAt, recordedBy },
        tx,
      );
      return { paymentId: payment.id, order, money: await settle(order, tx) };
    });

    notifications?.paymentRecorded({ order, amount, method: dto.method, money, recordedBy });
    return { payment: await getExisting(paymentId), ...money };
  }

  async function voidPayment(id, reason, voidedBy) {
    if (!reason?.trim()) throw badRequest('Give a reason for voiding this payment');
    const { money } = await db.transaction(async (tx) => {
      const current = await db.one('SELECT order_id AS orderId, status FROM payments WHERE id = ?', [id], tx);
      if (!current) throw notFound(`Payment ${id} not found`);
      const order = await lockOrder(current.orderId, tx);
      // Re-read under the order lock: two voids of the same payment cannot both succeed.
      const { status } = await db.one('SELECT status FROM payments WHERE id = ? FOR UPDATE', [id], tx);
      if (status === 'VOIDED') throw conflict('This payment has already been voided');
      await models.update('payment', id, { status: 'VOIDED', voidedBy, voidedAt: new Date(), voidReason: reason.trim() }, 'Payment', tx);
      return { money: await settle(order, tx) };
    });
    return { payment: await getExisting(id), ...money };
  }

  /** orders.view_own scoping for reads: another consultant's order's payments are "not found". */
  async function assertCanSeeOrder(orderId, userId) {
    const canViewTeam = await orders.hasPermission(userId, 'orders.view_team');
    await orders.findOneScoped(orderId, canViewTeam ? undefined : userId);
  }

  return { getExisting, listForOrder, findAll, record, voidPayment, summary, assertCanSeeOrder, paymentStatusFor };
}

// ---- Routes ------------------------------------------------------------------------------------

const money = num({ exclusiveMinimum: 0, maximum: 9_999_999_999.99, multipleOf: 0.01 });

function paymentsRoutes(app) {
  const { payments, orders, otp } = app.services;
  const { authenticate, requirePermissions } = app;

  /**
   * ?orderId=… — that order's payments + money summary (anyone who can see the order).
   * Without orderId — every payment in a period, for reporting (reports.view).
   */
  app.get(
    '/',
    {
      onRequest: [authenticate],
      schema: {
        querystring: obj({
          orderId: uuid,
          method: enumOf(PaymentMethod),
          status: enumOf(PaymentRecordStatus),
          from: dateString,
          to: dateString,
        }),
      },
    },
    async (request) => {
      if (request.query.orderId) {
        if (!(await orders.hasPermission(request.user.id, 'orders.view_own'))) throw forbidden('Insufficient permissions');
        await payments.assertCanSeeOrder(request.query.orderId, request.user.id);
        return payments.listForOrder(request.query.orderId);
      }
      if (!(await orders.hasPermission(request.user.id, 'reports.view'))) throw forbidden('Insufficient permissions');
      return payments.findAll(request.query);
    },
  );

  app.post(
    '/',
    {
      onRequest: [authenticate, requirePermissions('payments.record')],
      schema: {
        body: obj(
          {
            orderId: uuid,
            amount: money,
            method: enumOf(PaymentMethod),
            reference: opt(str({ maxLength: 191 })),
            notes: opt(str({ maxLength: 500 })),
            paidAt: opt(dateString),
          },
          ['orderId', 'amount', 'method'],
        ),
      },
    },
    async (request) => {
      const result = await payments.record(request.body, request.user.id);
      request.auditEntityId = result.payment.id;
      request.auditAction = 'RECORD_PAYMENT';
      return result;
    },
  );

  app.post(
    '/:id/void',
    {
      onRequest: [authenticate, requirePermissions('payments.void')],
      preHandler: [otp.requireOtp('payment.void')],
      schema: { params: uuidParams('id'), body: obj({ reason: str({ minLength: 1, maxLength: 500 }) }, ['reason']) },
    },
    async (request, res) => {
      request.auditOldValue = await payments.getExisting(request.params.id);
      request.auditAction = 'VOID_PAYMENT';
      res.status(200);
      return payments.voidPayment(request.params.id, request.body.reason, request.user.id);
    },
  );
}

module.exports = { createPaymentsService, paymentsRoutes };
