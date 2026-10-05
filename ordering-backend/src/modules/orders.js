'use strict';

const { badRequest, conflict, forbidden, notFound } = require('../core/errors');
const { cols, nest, groupBy, Where } = require('../core/models');
const { OrderStatus } = require('../core/enums');
const { obj, str, num, uuid, opt, arrayOf, enumOf, uuidParams } = require('../core/schema');
const { assertValidOrderTransition, ORDER_STATUSES_WITH_ACTIVE_RESERVATION } = require('./order-status-transitions');
const { planAllocation, byFifo } = require('./stock-allocation');

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

/** PERCENT/FIXED_AMOUNT/FIXED_PRICE -> a price, never negative. Mirrors warehouse-node's
 * products/service.js `discountedPrice` exactly — deliberately duplicated, no shared code across
 * systems (CLAUDE.md). Only needed for a RESTRICTED campaign; the warehouse already resolves
 * `effectivePrice` server-side for ALL_CUSTOMERS. */
function discountedPrice(sellingPrice, discountType, discountValue) {
  const raw =
    discountType === 'PERCENT'
      ? sellingPrice * (1 - discountValue / 100)
      : discountType === 'FIXED_AMOUNT'
        ? sellingPrice - discountValue
        : discountValue; // FIXED_PRICE
  return Math.max(0, Math.round(raw * 100) / 100);
}

function createOrdersService({ db, models, auth, customers, warehouseApi, notifications, salesEligibility }) {
  async function loadOrders(where = new Where(), orderBy = 'ORDER BY o.created_at DESC', executor) {
    const orders = (await db.query(`${ORDER_SELECT} ${where.sql} ${orderBy}`, where.params, executor)).map(nest);
    if (orders.length === 0) return orders;
    const ids = orders.map((o) => o.id);
    const [items, history, allocations] = await Promise.all([
      db.query(`SELECT ${cols('orderItem', 'i')} FROM order_items i WHERE i.order_id IN (?) ORDER BY i.order_id, i.id`, [ids], executor),
      db.query(
        `SELECT ${cols('orderStatusHistory', 'h')}, ${cols('user', 'u', ['id', 'fullName'], 'changedByUser.')}
           FROM order_status_history h JOIN users u ON u.id = h.changed_by
          WHERE h.order_id IN (?)
          ORDER BY h.created_at ASC`,
        [ids],
        executor,
      ),
      db.query(
        `SELECT a.order_item_id AS orderItemId, a.location_id AS locationId, a.location_label AS locationLabel, a.quantity
           FROM order_item_allocations a JOIN order_items i ON i.id = a.order_item_id
          WHERE i.order_id IN (?)
          ORDER BY a.order_item_id, a.position`,
        [ids],
        executor,
      ),
    ]);
    // Where each line's stock is reserved (several locations when a line was split).
    const allocationsByItem = groupBy(allocations, 'orderItemId');
    for (const item of items) {
      item.allocations = (allocationsByItem.get(item.id) ?? []).map(({ locationId, locationLabel, quantity }) => ({
        locationId,
        locationLabel,
        quantity,
      }));
    }
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
   *
   * A product carrying a `sale` block (warehouse-node's attachActiveSale) gets its discount applied
   * HERE, once the minimum quantity and eligibility are both satisfied — `effectivePrice` is used
   * directly for an ALL_CUSTOMERS campaign (the warehouse already resolved it); a RESTRICTED one is
   * resolved locally, since the warehouse never learns which customer is ordering (ARCHITECTURE.md).
   */
  /** How many of this customer's own orders (any status but CANCELLED/REJECTED — a DRAFT still
   * counts, since saving a draft re-runs this check anyway and an uncapped draft wouldn't) already
   * carry this campaign — the per-customer usage cap's enforcement point, since the warehouse has no
   * concept of a customer at all (ARCHITECTURE.md) and so cannot count this itself. */
  async function campaignUsesByCustomer(campaignId, customerId) {
    const row = await db.one(
      `SELECT COUNT(DISTINCT oi.order_id) AS n
         FROM order_items oi
         JOIN orders o ON o.id = oi.order_id
        WHERE oi.sale_campaign_id = ? AND o.customer_id = ? AND o.status NOT IN ('CANCELLED', 'REJECTED')`,
      [campaignId, customerId],
    );
    return Number(row.n);
  }

  function buildLineInputs(items, customerId) {
    return Promise.all(
      items.map(async (item) => {
        const product = await warehouseApi.getProduct(item.productId);
        if (product.status !== 'ACTIVE') throw badRequest(`Product ${product.sku} is not active and cannot be ordered`);
        let unitPrice = Number(product.sellingPrice);
        let originalUnitPrice = null;
        let saleCampaignId = null;
        let saleCampaignName = null;
        if (product.sale) {
          const meetsQty = item.quantity >= Number(product.sale.minQuantity);
          const eligible =
            product.sale.eligibility === 'ALL_CUSTOMERS' || (await salesEligibility.isEligible(product.sale.campaignId, customerId));
          const underCap =
            product.sale.maxUsesPerCustomer === undefined ||
            (await campaignUsesByCustomer(product.sale.campaignId, customerId)) < product.sale.maxUsesPerCustomer;
          if (meetsQty && eligible && underCap) {
            originalUnitPrice = unitPrice;
            unitPrice =
              product.sale.effectivePrice !== undefined
                ? Number(product.sale.effectivePrice)
                : discountedPrice(unitPrice, product.sale.discountType, Number(product.sale.discountValue));
            saleCampaignId = product.sale.campaignId;
            saleCampaignName = product.sale.campaignName;
          }
        }
        return {
          productId: item.productId,
          productName: product.name,
          quantityOrdered: item.quantity,
          unitPrice,
          originalUnitPrice,
          saleCampaignId,
          saleCampaignName,
          // A snapshot, same principle as originalUnitPrice above — null when the warehouse product
          // has no cost_price set (never treated as 0; see modules/finances.js's margin query).
          unitCost: product.costPrice == null ? null : Number(product.costPrice),
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
    const lines = await buildLineInputs(dto.items, dto.customerId);
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

    const lines = dto.items ? await buildLineInputs(dto.items, order.customerId) : undefined;
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

  /** Human names for warehouse locations: "Rack A › Shelf 2", from the warehouse's flat parentId list. */
  function locationDirectory({ warehouses = [], locations = [] }) {
    const byId = new Map(locations.map((l) => [l.id, l]));
    const warehouseById = new Map(warehouses.map((w) => [w.id, w]));
    const path = (id) => {
      const names = [];
      for (let l = byId.get(id), guard = 0; l && guard < 50; l = byId.get(l.parentId), guard++) names.unshift(l.name);
      return names.join(' › ');
    };
    return {
      has: (id) => byId.has(id),
      warehouseOf: (id) => byId.get(id)?.warehouseId ?? null,
      label: (id) => (byId.has(id) ? path(id) : id),
      warehouse: (id) => {
        const w = warehouseById.get(id);
        return w ? { id: w.id, name: w.name, code: w.code } : { id, name: id, code: null };
      },
    };
  }

  /**
   * The automatic reservation plan for an APPROVED order (modules/stock-allocation.js): one warehouse,
   * oldest stock first, lines split across locations when needed. Each line also lists every location
   * in that warehouse holding the product, so a manager can override the plan. `warehouseId` asks for
   * the plan in a specific warehouse instead of the best one.
   */
  async function proposeReservation(id, { warehouseId } = {}) {
    const order = await getExisting(id);
    assertValidOrderTransition(order.status, 'STOCK_RESERVED');
    const productIds = [...new Set(order.items.map((i) => i.productId))];
    const [options, directory] = await Promise.all([
      warehouseApi.allocationOptions(productIds),
      warehouseApi.getLocations().then(locationDirectory),
    ]);
    const plan = planAllocation(
      order.items.map((i) => ({ id: i.id, productId: i.productId, quantity: Number(i.quantityOrdered) })),
      options.products,
      { warehouseId },
    );
    const optionsByProduct = new Map(options.products.map((p) => [p.productId, p.locations]));
    const planByItem = new Map(plan.lines.map((l) => [l.orderItemId, l]));
    const describe = (loc) => ({
      locationId: loc.locationId,
      label: directory.label(loc.locationId),
      available: loc.available,
      oldestStockAt: loc.oldestStockAt,
    });

    return {
      orderId: order.id,
      complete: plan.complete,
      warehouse: plan.warehouseId ? directory.warehouse(plan.warehouseId) : null,
      alternatives: plan.alternatives.map((a) => ({ ...directory.warehouse(a.warehouseId), complete: a.complete })),
      lines: order.items.map((item) => {
        const planned = planByItem.get(item.id);
        const here = (optionsByProduct.get(item.productId) ?? []).filter((l) => l.warehouseId === plan.warehouseId).sort(byFifo);
        const hereById = new Map(here.map((l) => [l.locationId, l]));
        return {
          orderItemId: item.id,
          productId: item.productId,
          productName: item.productName,
          quantity: Number(item.quantityOrdered),
          allocations: planned.allocations.map((a) => ({ ...describe(hereById.get(a.locationId)), quantity: a.quantity })),
          shortBy: planned.shortBy,
          options: here.map(describe),
        };
      }),
    };
  }

  /**
   * APPROVED -> STOCK_RESERVED via the warehouse's idempotent reserve (reference = order id, so a
   * retry replays rather than doubles).
   *
   * With no `allocations`, the automatic plan is used (proposeReservation) — refused with the short
   * lines when no single warehouse can fill the order. With `allocations` (a manager's override), each
   * entry is { orderItemId, locationId, quantity? }: every line must be covered exactly (quantity may be
   * omitted when a line comes from one location), and all locations must be in ONE warehouse.
   * Either way the warehouse checks availability atomically: a location without enough stock makes the
   * whole reservation fail — nothing is written locally, the order stays APPROVED, and the short lines
   * come back in the 409.
   */
  async function reserve(id, dto, changedBy) {
    const order = await getExisting(id);
    assertValidOrderTransition(order.status, 'STOCK_RESERVED');
    const itemById = new Map(order.items.map((i) => [i.id, i]));

    let allocations; // [{ orderItemId, locationId, quantity }]
    let directory; // location names, snapshotted onto the allocations
    if (!dto.allocations?.length) {
      const plan = await proposeReservation(id, { warehouseId: dto.warehouseId ?? undefined });
      if (!plan.complete) {
        const short = plan.lines.filter((l) => l.shortBy > 0);
        throw conflict(
          plan.warehouse
            ? `Cannot reserve — no single warehouse has enough stock for this whole order (closest: ${plan.warehouse.name}). Short: ` +
                short.map((l) => `${l.productName ?? l.productId} by ${l.shortBy}`).join('; ')
            : 'Cannot reserve — none of the products on this order is in stock in any warehouse',
          {
            shortLines: short.map((l) => ({
              orderItemId: l.orderItemId,
              productId: l.productId,
              requested: l.quantity,
              available: round3(l.quantity - l.shortBy),
            })),
          },
        );
      }
      allocations = plan.lines.flatMap((l) =>
        l.allocations.map((a) => ({ orderItemId: l.orderItemId, locationId: a.locationId, quantity: a.quantity })),
      );
    } else {
      assertItemCoverage(order.items, [...new Set(dto.allocations.map((a) => a.orderItemId))], 'Allocations');
      const merged = new Map(); // orderItemId:locationId -> entry
      for (const a of dto.allocations) {
        const item = itemById.get(a.orderItemId);
        const entriesForItem = dto.allocations.filter((x) => x.orderItemId === a.orderItemId).length;
        if (a.quantity == null && entriesForItem > 1) {
          throw badRequest('When a line is split across locations, give each location its quantity');
        }
        const quantity = round3(a.quantity ?? Number(item.quantityOrdered));
        const key = `${a.orderItemId}:${a.locationId}`;
        const prev = merged.get(key);
        merged.set(key, { orderItemId: a.orderItemId, locationId: a.locationId, quantity: round3((prev?.quantity ?? 0) + quantity) });
      }
      allocations = [...merged.values()];
      for (const item of order.items) {
        const total = round3(allocations.filter((a) => a.orderItemId === item.id).reduce((sum, a) => sum + a.quantity, 0));
        if (Math.abs(total - Number(item.quantityOrdered)) > 0.0005) {
          throw badRequest(
            `The locations for ${item.productName ?? item.productId} add up to ${total}, but the line is for ${Number(item.quantityOrdered)}`,
          );
        }
      }
      directory = locationDirectory(await warehouseApi.getLocations());
      const unknown = allocations.find((a) => !directory.has(a.locationId));
      if (unknown) throw badRequest(`Location ${unknown.locationId} is not an active warehouse location`);
      if (new Set(allocations.map((a) => directory.warehouseOf(a.locationId))).size > 1) {
        throw badRequest("All of an order's stock must come from one warehouse");
      }
    }

    // The warehouse holds one reservation line per product + location: lines of the same product
    // reserved at the same location are sent together.
    const warehouseLines = new Map();
    for (const a of allocations) {
      const productId = itemById.get(a.orderItemId).productId;
      const key = `${productId}:${a.locationId}`;
      const line = warehouseLines.get(key) ?? { productId, locationId: a.locationId, quantity: 0 };
      line.quantity = round3(line.quantity + a.quantity);
      warehouseLines.set(key, line);
    }

    // The label is what warehouse packers see on their packing list.
    const result = await warehouseApi.reserve(order.id, [...warehouseLines.values()], `${order.orderNumber} · ${order.customer.name}`);
    if (!result.success) {
      const detail = result.shortLines
        .map((l) => `product ${l.productId} at location ${l.locationId}: need ${l.requested}, only ${l.available} available`)
        .join('; ');
      throw conflict(`Cannot reserve — insufficient available stock for: ${detail}`, { shortLines: result.shortLines });
    }

    directory ??= locationDirectory(await warehouseApi.getLocations());
    await db.transaction(async (tx) => {
      await db.exec(
        'DELETE a FROM order_item_allocations a JOIN order_items i ON i.id = a.order_item_id WHERE i.order_id = ?',
        [order.id],
        tx,
      );
      await models.insertMany(
        'orderItemAllocation',
        allocations.map((a, position) => ({
          orderItemId: a.orderItemId,
          locationId: a.locationId,
          locationLabel: directory.label(a.locationId),
          quantity: a.quantity,
          position,
        })),
        tx,
      );
      for (const item of order.items) {
        const first = allocations.find((a) => a.orderItemId === item.id);
        await models.update('orderItem', item.id, { reservedLocationId: first.locationId }, 'Order item', tx);
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

    // Where each line was reserved, in the order it was planned (oldest stock first). A line reserved
    // before per-location allocations existed has just its reservedLocationId, for its whole quantity.
    const plannedByItem = new Map(
      order.items.map((item) => {
        const planned = item.allocations.length
          ? item.allocations.map((a) => ({ locationId: a.locationId, quantity: Number(a.quantity) }))
          : item.reservedLocationId
            ? [{ locationId: item.reservedLocationId, quantity: Number(item.quantityOrdered) }]
            : [];
        if (!planned.length) {
          throw conflict(`No reservation location recorded for product ${item.productId} on this order — cannot dispatch`);
        }
        return [item.id, planned];
      }),
    );

    // Ship exactly what was packed, taken from each line's locations in plan order. The warehouse
    // releases whatever was reserved but not shipped.
    const issueByKey = new Map(); // productId:locationId -> { productId, locationId, quantity }
    const takesByItem = new Map(); // orderItemId -> [{ key, quantity }]
    for (const item of order.items) {
      let toShip = Number(item.quantityPacked);
      const takes = [];
      for (const planned of plannedByItem.get(item.id)) {
        if (toShip <= 0) break;
        const take = round3(Math.min(toShip, planned.quantity));
        const key = `${item.productId}:${planned.locationId}`;
        const line = issueByKey.get(key) ?? { productId: item.productId, locationId: planned.locationId, quantity: 0 };
        line.quantity = round3(line.quantity + take);
        issueByKey.set(key, line);
        takes.push({ key, quantity: take });
        toShip = round3(toShip - take);
      }
      takesByItem.set(item.id, takes);
    }
    const issueLines = [...issueByKey.values()].filter((l) => l.quantity > 0);

    let issuedByKey = new Map();
    if (issueLines.length > 0) {
      const result = await warehouseApi.issue(order.id, issueLines);
      issuedByKey = new Map(result.issued.map((l) => [`${l.productId}:${l.locationId}`, Number(l.issued)]));
    } else {
      await warehouseApi.release(order.id);
    }

    // quantityFulfilled comes ONLY from what the warehouse says it issued, shared back to the lines.
    const operations = order.items.map((item) => {
      let fulfilledQty = 0;
      for (const take of takesByItem.get(item.id)) {
        const left = issuedByKey.get(take.key) ?? 0;
        const got = round3(Math.min(left, take.quantity));
        issuedByKey.set(take.key, round3(left - got));
        fulfilledQty = round3(fulfilledQty + got);
      }
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
    proposeReservation,
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
  // The automatic plan (one warehouse, oldest stock first, split lines) a manager can accept or override.
  app.get(
    '/:id/reservation-proposal',
    { onRequest: guard('orders.approve'), schema: { ...idParams, querystring: obj({ warehouseId: uuid }) } },
    async (request) => orders.proposeReservation(request.params.id, request.query),
  );
  // No `allocations` = reserve per the automatic plan; with them = the manager's override.
  action(
    'reserve',
    'orders.approve',
    'RESERVE',
    obj({
      warehouseId: opt(uuid),
      allocations: opt(
        arrayOf(obj({ orderItemId: uuid, locationId: uuid, quantity: opt(qty3({ exclusiveMinimum: 0 })) }, ['orderItemId', 'locationId']), {
          minItems: 1,
        }),
      ),
    }),
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
