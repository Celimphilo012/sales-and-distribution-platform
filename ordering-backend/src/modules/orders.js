'use strict';

const { badRequest, conflict, forbidden, notFound } = require('../core/errors');
const { cols, nest, groupBy, Where } = require('../core/models');
const { OrderStatus } = require('../core/enums');
const { obj, str, num, uuid, opt, arrayOf, enumOf, uuidParams } = require('../core/schema');
const { assertValidOrderTransition, ORDER_STATUSES_WITH_ACTIVE_RESERVATION } = require('./order-status-transitions');

const round2 = (n) => Math.round(n * 100) / 100;
const round3 = (n) => Math.round(n * 1000) / 1000;

function generateOrderNumberCandidate() {
  const datePart = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const randomPart = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `ORD-${datePart}-${randomPart}`;
}

/**
 * An order read: the order + amountPaid (its RECORDED payments) + customer { id, name, phone } + consultant { id, fullName, email } |
 * null + items (each carrying its own catalogue snapshot — the product lives in warehouse_db, no FK
 * across the boundary) + statusHistory (oldest first, each with changedByUser { id, fullName }).
 */
const ORDER_SELECT = `
  SELECT ${cols('order', 'o')},
         (SELECT COALESCE(SUM(pay.amount), 0) FROM payments pay
           WHERE pay.order_id = o.id AND pay.status = 'RECORDED') AS amountPaid,
         ${cols('customer', 'c', ['id', 'name', 'phone'], 'customer.')},
         ${cols('user', 'u', ['id', 'fullName', 'email'], 'consultant.')}
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
    LEFT JOIN users u ON u.id = o.consultant_id`;

function createOrdersService({ db, models, auth, customers, warehouseApi, notifications }) {
  async function loadOrders(where = new Where(), orderBy = 'ORDER BY o.created_at DESC', executor) {
    const orders = (await db.query(`${ORDER_SELECT} ${where.sql} ${orderBy}`, where.params, executor)).map(nest);
    if (orders.length === 0) return orders;
    const ids = orders.map((o) => o.id);
    const [items, history] = await Promise.all([
      db.query(`SELECT ${cols('orderItem', 'i')} FROM order_items i WHERE i.order_id IN (?) ORDER BY i.order_id, i.id`, [ids], executor),
      db.query(
        `SELECT ${cols('orderStatusHistory', 'h')}, ${cols('user', 'u', ['id', 'fullName'], 'changedByUser.')}
           FROM order_status_history h JOIN users u ON u.id = h.changed_by
          WHERE h.order_id IN (?)
          ORDER BY h.created_at ASC`,
        [ids],
        executor,
      ),
    ]);
    const itemsByOrder = groupBy(items, 'orderId');
    const historyByOrder = groupBy(history.map(nest), 'orderId');
    return orders.map((o) => ({ ...o, items: itemsByOrder.get(o.id) ?? [], statusHistory: historyByOrder.get(o.id) ?? [] }));
  }

  const hasPermission = (userId, key) => auth.hasPermission(userId, key);

  function findAll(query, scopeToUserId) {
    const where = new Where().eq('o.status', query.status).eq('o.customer_id', query.customerId).eq('o.consultant_id', scopeToUserId);
    return loadOrders(where);
  }

  async function getExisting(id) {
    const [order] = await loadOrders(new Where().eq('o.id', id), '');
    if (!order) throw notFound(`Order ${id} not found`);
    return order;
  }

  /** orders.view_own scoping: another consultant's order is reported as not found, not forbidden. */
  async function findOneScoped(id, scopeToUserId) {
    const order = await getExisting(id);
    if (scopeToUserId && order.consultantId !== scopeToUserId) throw notFound(`Order ${id} not found`);
    return order;
  }

  /**
   * Rule 8 across the split: every line's name + price is snapshotted from the warehouse catalogue
   * at save time — never client-supplied. An INACTIVE product is rejected.
   */
  function buildLineInputs(items) {
    return Promise.all(
      items.map(async (item) => {
        const product = await warehouseApi.getProduct(item.productId);
        if (product.status !== 'ACTIVE') throw badRequest(`Product ${product.sku} is not active and cannot be ordered`);
        const unitPrice = Number(product.sellingPrice);
        return {
          productId: item.productId,
          productName: product.name,
          quantityOrdered: item.quantity,
          unitPrice,
          lineTotal: round2(unitPrice * item.quantity),
        };
      }),
    );
  }

  async function generateUniqueOrderNumber() {
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = generateOrderNumberCandidate();
      if (!(await db.one('SELECT id FROM orders WHERE order_number = ?', [candidate]))) return candidate;
    }
    throw conflict('Could not generate a unique order number — please retry');
  }

  async function applyTransition(tx, orderId, from, to, changedBy, note) {
    assertValidOrderTransition(from, to);
    await models.update('order', orderId, { status: to }, 'Order', tx);
    await models.insert('orderStatusHistory', { orderId, fromStatus: from, toStatus: to, changedBy, note: note ?? null }, tx);
  }

  async function create(dto, consultantId) {
    await customers.getExisting(dto.customerId);
    const lines = await buildLineInputs(dto.items);
    const total = round2(lines.reduce((sum, l) => sum + l.lineTotal, 0));
    const orderNumber = await generateUniqueOrderNumber();

    const orderId = await db.transaction(async (tx) => {
      const order = await models.insert(
        'order',
        { orderNumber, customerId: dto.customerId, consultantId, deliveryInfo: dto.deliveryInfo, total },
        tx,
      );
      await models.insertMany('orderItem', lines.map((l) => ({ ...l, orderId: order.id })), tx);
      await models.insert(
        'orderStatusHistory',
        { orderId: order.id, fromStatus: null, toStatus: 'DRAFT', changedBy: consultantId, note: 'Order created' },
        tx,
      );
      return order.id;
    });
    return getExisting(orderId);
  }

  /** DRAFT-only, owner-only. `items`, when given, REPLACES the full set. */
  async function update(id, dto, userId) {
    const order = await getExisting(id);
    if (order.status !== 'DRAFT') throw conflict('Only DRAFT orders can be edited');
    if (order.consultantId !== userId) throw forbidden("Only the order's owner can edit their own draft");

    const lines = dto.items ? await buildLineInputs(dto.items) : undefined;
    const total = lines ? round2(lines.reduce((sum, l) => sum + l.lineTotal, 0)) : undefined;

    await db.transaction(async (tx) => {
      if (lines) {
        await db.exec('DELETE FROM order_items WHERE order_id = ?', [id], tx);
        await models.insertMany('orderItem', lines.map((l) => ({ ...l, orderId: id })), tx);
      }
      await models.update('order', id, { deliveryInfo: dto.deliveryInfo, total }, 'Order', tx);
    });
    return getExisting(id);
  }

  /** One-step status hops that only need the transition map. */
  async function simpleTransition(id, to, changedBy, note) {
    const order = await getExisting(id);
    await db.transaction((tx) => applyTransition(tx, order.id, order.status, to, changedBy, note));
    const updated = await getExisting(id);
    notifications?.orderStatusChanged(updated, to, changedBy, note);
    return updated;
  }

  /** DRAFT -> SUBMITTED -> PENDING_APPROVAL: one user action, two history rows. */
  async function submit(id, changedBy, note) {
    const order = await getExisting(id);
    await db.transaction(async (tx) => {
      await applyTransition(tx, order.id, order.status, 'SUBMITTED', changedBy, note);
      await applyTransition(tx, order.id, 'SUBMITTED', 'PENDING_APPROVAL', changedBy, note);
    });
    const updated = await getExisting(id);
    notifications?.orderSubmitted(updated, changedBy);
    return updated;
  }

  function assertItemCoverage(orderItems, providedIds, label = 'Items') {
    const itemIds = new Set(orderItems.map((i) => i.id));
    const provided = new Set(providedIds);
    const missing = [...itemIds].filter((i) => !provided.has(i));
    const extra = [...provided].filter((i) => !itemIds.has(i));
    if (missing.length || extra.length) {
      throw badRequest(
        `${label} must cover exactly this order's items.` +
          (missing.length ? ` Missing: ${missing.join(', ')}.` : '') +
          (extra.length ? ` Not part of this order: ${extra.join(', ')}.` : ''),
      );
    }
  }

  /**
   * APPROVED -> STOCK_RESERVED via the warehouse's idempotent reserve (reference = order id, so a
   * retry replays rather than doubles). A shortfall is a business outcome: nothing is written
   * locally, the order stays APPROVED, and the short lines come back in the 409.
   */
  async function reserve(id, dto, changedBy) {
    const order = await getExisting(id);
    assertValidOrderTransition(order.status, 'STOCK_RESERVED');
    assertItemCoverage(order.items, dto.allocations.map((a) => a.orderItemId), 'Allocations');

    const itemById = new Map(order.items.map((i) => [i.id, i]));
    const lines = dto.allocations.map((a) => ({
      productId: itemById.get(a.orderItemId).productId,
      locationId: a.locationId,
      quantity: Number(itemById.get(a.orderItemId).quantityOrdered),
    }));

    // The label is what warehouse packers see on their packing list.
    const result = await warehouseApi.reserve(order.id, lines, `${order.orderNumber} · ${order.customer.name}`);
    if (!result.success) {
      const detail = result.shortLines
        .map((l) => `product ${l.productId} at location ${l.locationId}: need ${l.requested}, only ${l.available} available`)
        .join('; ');
      throw conflict(`Cannot reserve — insufficient available stock for: ${detail}`, { shortLines: result.shortLines });
    }

    await db.transaction(async (tx) => {
      for (const a of dto.allocations) {
        await models.update('orderItem', a.orderItemId, { reservedLocationId: a.locationId }, 'Order item', tx);
      }
      await applyTransition(tx, order.id, 'APPROVED', 'STOCK_RESERVED', changedBy, undefined);
    });
    return getExisting(id);
  }

  /**
   * -> CANCELLED. An order holding a reservation releases it in the warehouse FIRST (idempotent);
   * if the warehouse is unreachable this throws and the order stays as it was.
   */
  async function cancel(id, changedBy, note) {
    const order = await getExisting(id);
    // Money recorded against an order must be dealt with (returned, then voided) before it is
    // cancelled — a cancelled order never silently keeps a customer's payment (rule 6).
    if (Number(order.amountPaid) > 0) {
      throw conflict(
        `Order ${order.orderNumber} has payments recorded (E ${Number(order.amountPaid).toFixed(2)}) — void them before cancelling`,
      );
    }
    if (ORDER_STATUSES_WITH_ACTIVE_RESERVATION.includes(order.status)) await warehouseApi.release(order.id);
    await db.transaction((tx) => applyTransition(tx, order.id, order.status, 'CANCELLED', changedBy, note));
    const updated = await getExisting(id);
    notifications?.orderStatusChanged(updated, 'CANCELLED', changedBy, note);
    return updated;
  }

  /** Picking/packing are physical confirmations — no stock effect. */
  async function recordQuantities(id, entries, to, qtyField, limitField, verb, changedBy, note) {
    const order = await getExisting(id);
    assertValidOrderTransition(order.status, to);
    assertItemCoverage(order.items, entries.map((e) => e.orderItemId));
    const itemById = new Map(order.items.map((i) => [i.id, i]));
    for (const entry of entries) {
      const item = itemById.get(entry.orderItemId);
      const limit = Number(item[limitField]);
      if (entry.qty > limit) {
        throw badRequest(
          `${verb} quantity for product ${item.productId} (${entry.qty}) cannot exceed ${limitField === 'quantityOrdered' ? 'ordered' : 'picked'} quantity (${limit})`,
        );
      }
    }
    await db.transaction(async (tx) => {
      for (const entry of entries) {
        await models.update('orderItem', entry.orderItemId, { [qtyField]: entry.qty }, 'Order item', tx);
      }
      await applyTransition(tx, order.id, order.status, to, changedBy, note);
    });
    return getExisting(id);
  }

  const pick = (id, dto, changedBy) =>
    recordQuantities(id, dto.items.map((i) => ({ orderItemId: i.orderItemId, qty: i.pickedQty })), 'PICKING', 'quantityPicked', 'quantityOrdered', 'Picked', changedBy);

  const pack = (id, dto, changedBy) =>
    recordQuantities(id, dto.items.map((i) => ({ orderItemId: i.orderItemId, qty: i.packedQty })), 'PACKED', 'quantityPacked', 'quantityPicked', 'Packed', changedBy);

  /**
   * READY_FOR_DISPATCH -> DISPATCHED / PARTIALLY_FULFILLED — the stock deduction point. Ships exactly
   * what was packed, from the location each line was reserved at, in ONE warehouse issue call (which
   * also releases whatever was reserved but not packed). quantityFulfilled and the final status come
   * ONLY from the warehouse's answer. If nothing was packed at all, release instead.
   */
  async function dispatch(id, changedBy, note) {
    const order = await getExisting(id);
    if (order.status !== 'READY_FOR_DISPATCH') throw conflict(`Cannot transition order from ${order.status} to DISPATCHED`);
    for (const item of order.items) {
      if (!item.reservedLocationId) {
        throw conflict(`No reservation location recorded for product ${item.productId} on this order — cannot dispatch`);
      }
    }

    const issueLines = order.items
      .filter((item) => Number(item.quantityPacked) > 0)
      .map((item) => ({ productId: item.productId, locationId: item.reservedLocationId, quantity: Number(item.quantityPacked) }));

    let issuedByLine = new Map();
    if (issueLines.length > 0) {
      const result = await warehouseApi.issue(order.id, issueLines);
      issuedByLine = new Map(result.issued.map((l) => [`${l.productId}|${l.locationId}`, l.issued]));
    } else {
      await warehouseApi.release(order.id);
    }

    const operations = order.items.map((item) => {
      const fulfilledQty = issuedByLine.get(`${item.productId}|${item.reservedLocationId}`) ?? 0;
      return { orderItemId: item.id, fulfilledQty, remainder: round3(Number(item.quantityOrdered) - fulfilledQty) };
    });
    const finalStatus = operations.some((op) => op.remainder > 0) ? 'PARTIALLY_FULFILLED' : 'DISPATCHED';
    assertValidOrderTransition(order.status, finalStatus);

    await db.transaction(async (tx) => {
      for (const op of operations) {
        await models.update('orderItem', op.orderItemId, { quantityFulfilled: op.fulfilledQty }, 'Order item', tx);
      }
      await applyTransition(tx, order.id, order.status, finalStatus, changedBy, note);
    });
    const updated = await getExisting(id);
    notifications?.orderStatusChanged(updated, finalStatus, changedBy, note);
    return updated;
  }

  return {
    hasPermission,
    findAll,
    getExisting,
    findOneScoped,
    create,
    update,
    submit,
    approve: (id, by, note) => simpleTransition(id, 'APPROVED', by, note),
    reject: (id, by, note) => simpleTransition(id, 'REJECTED', by, note),
    reserve,
    cancel,
    pick,
    pack,
    ready: (id, by, note) => simpleTransition(id, 'READY_FOR_DISPATCH', by, note),
    dispatch,
    deliver: (id, by, note) => simpleTransition(id, 'DELIVERED', by, note),
    complete: (id, by, note) => simpleTransition(id, 'COMPLETED', by, note),
  };
}

// ---- Routes ------------------------------------------------------------------------------------

const qty3 = (extra) => num({ multipleOf: 0.001, ...extra });
const itemInput = obj({ productId: uuid, quantity: qty3({ exclusiveMinimum: 0 }) }, ['productId', 'quantity']);
const noteBody = obj({ note: opt(str()) });

function ordersRoutes(app) {
  const { orders } = app.services;
  const guard = (key) => [app.authenticate, app.requirePermissions(key)];
  const idParams = { params: uuidParams('id') };

  // Gated by the minimal common key; whether the result is "own" or everyone's is decided by
  // orders.view_team (the guard is AND-only across its declared keys).
  app.get(
    '/',
    { onRequest: guard('orders.view_own'), schema: { querystring: obj({ status: enumOf(OrderStatus), customerId: uuid }) } },
    async (request) => {
      const canViewTeam = await orders.hasPermission(request.user.id, 'orders.view_team');
      return orders.findAll(request.query, canViewTeam ? undefined : request.user.id);
    },
  );

  app.get('/:id', { onRequest: guard('orders.view_own'), schema: idParams }, async (request) => {
    const canViewTeam = await orders.hasPermission(request.user.id, 'orders.view_team');
    return orders.findOneScoped(request.params.id, canViewTeam ? undefined : request.user.id);
  });

  app.post(
    '/',
    {
      onRequest: guard('orders.create'),
      schema: {
        body: obj({ customerId: uuid, deliveryInfo: opt(str()), items: arrayOf(itemInput, { minItems: 1 }) }, ['customerId', 'items']),
      },
    },
    async (request) => orders.create(request.body, request.user.id),
  );

  app.patch(
    '/:id',
    {
      onRequest: guard('orders.edit_own_draft'),
      schema: { ...idParams, body: obj({ deliveryInfo: opt(str()), items: opt(arrayOf(itemInput, { minItems: 1 })) }) },
    },
    async (request) => {
      request.auditOldValue = await orders.getExisting(request.params.id);
      return orders.update(request.params.id, request.body, request.user.id);
    },
  );

  // Approve / reject / cancel are confirmed with a one-time code (catalog/otp-actions.js).
  const OTP_BY_PATH = { approve: 'order.approve', reject: 'order.reject', cancel: 'order.cancel' };
  const action = (path, permission, verb, bodySchema, run) =>
    app.post(
      `/:id/${path}`,
      {
        onRequest: guard(permission),
        preHandler: OTP_BY_PATH[path] ? [app.services.otp.requireOtp(OTP_BY_PATH[path])] : [],
        schema: { ...idParams, body: bodySchema },
      },
      async (request) => {
        request.auditAction = verb;
        return run(request.params.id, request.body, request.user.id);
      },
    );

  action('submit', 'orders.submit', 'SUBMIT', noteBody, (id, b, by) => orders.submit(id, by, b.note ?? undefined));
  action('approve', 'orders.approve', 'APPROVE', noteBody, (id, b, by) => orders.approve(id, by, b.note ?? undefined));
  action('reject', 'orders.reject', 'REJECT', obj({ note: str({ minLength: 1 }) }, ['note']), (id, b, by) => {
    // A whitespace-only reason is no reason (the UI trims; the API must too).
    if (!b.note.trim()) throw badRequest('note should not be empty');
    return orders.reject(id, by, b.note);
  });
  action(
    'reserve',
    'orders.approve',
    'RESERVE',
    obj({ allocations: arrayOf(obj({ orderItemId: uuid, locationId: uuid }, ['orderItemId', 'locationId']), { minItems: 1 }) }, [
      'allocations',
    ]),
    (id, b, by) => orders.reserve(id, b, by),
  );
  action('cancel', 'orders.approve', 'CANCEL', noteBody, (id, b, by) => orders.cancel(id, by, b.note ?? undefined));
  action(
    'pick',
    'fulfilment.pick',
    'PICK',
    obj({ items: arrayOf(obj({ orderItemId: uuid, pickedQty: qty3({ minimum: 0 }) }, ['orderItemId', 'pickedQty']), { minItems: 1 }) }, ['items']),
    (id, b, by) => orders.pick(id, b, by),
  );
  action(
    'pack',
    'fulfilment.pack',
    'PACK',
    obj({ items: arrayOf(obj({ orderItemId: uuid, packedQty: qty3({ minimum: 0 }) }, ['orderItemId', 'packedQty']), { minItems: 1 }) }, ['items']),
    (id, b, by) => orders.pack(id, b, by),
  );
  action('ready', 'fulfilment.dispatch', 'READY', noteBody, (id, b, by) => orders.ready(id, by, b.note ?? undefined));
  action('dispatch', 'fulfilment.dispatch', 'DISPATCH', noteBody, (id, b, by) => orders.dispatch(id, by, b.note ?? undefined));
  action('deliver', 'fulfilment.dispatch', 'DELIVER', noteBody, (id, b, by) => orders.deliver(id, by, b.note ?? undefined));
  // /complete stays in the same hands as /deliver — the tail of the same fulfilment workflow.
  action('complete', 'fulfilment.dispatch', 'COMPLETE', noteBody, (id, b, by) => orders.complete(id, by, b.note ?? undefined));
}

/** Frontend-facing relays over the warehouse API client (the frontend never talks to the warehouse). */
function catalogueRoutes(app) {
  // Always ACTIVE-only: a picker should never offer a product the order save would reject.
  app.get(
    '/',
    { onRequest: [app.authenticate, app.requirePermissions('orders.create')], schema: { querystring: obj({ search: str() }) } },
    async (request) => app.services.warehouseApi.getCatalogue({ search: request.query.search, status: 'ACTIVE' }),
  );
}

function warehouseLocationsRoutes(app) {
  // Only reserving an order's stock needs locations, and that is gated orders.approve too.
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('orders.approve')] }, async () =>
    app.services.warehouseApi.getLocations(),
  );
}

module.exports = { createOrdersService, ordersRoutes, catalogueRoutes, warehouseLocationsRoutes };
