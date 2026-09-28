'use strict';

const { conflict, forbidden, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, nest, Where } = require('../../core/models');
const { AdjustmentStatus } = require('../../core/enums');

const BUCKET_MAP = {
  ON_HAND: 'onHand',
  RESERVED: 'reserved',
  DAMAGED: 'damaged',
  LOST: 'lost',
  EXPIRED: 'expired',
};

// The adjustment plus product / location / requester / reviewer summaries (reviewer is null until reviewed).
const ADJUSTMENT_SELECT = `
  SELECT ${cols('stockAdjustment', 'a')},
         ${cols('product', 'p', ['id', 'sku', 'name'], 'product.')},
         ${cols('location', 'l', ['id', 'name', 'code', 'warehouseId'], 'location.')},
         ${cols('user', 'ru', ['id', 'fullName', 'email'], 'requestedByUser.')},
         ${cols('user', 'vu', ['id', 'fullName', 'email'], 'reviewedByUser.')}
    FROM stock_adjustments a
    JOIN products p ON p.id = a.product_id
    JOIN locations l ON l.id = a.location_id
    JOIN users ru ON ru.id = a.requested_by
    LEFT JOIN users vu ON vu.id = a.reviewed_by`;

class StockAdjustmentsService {
  constructor({ db, models, access, notifications }, productsService, locationsService, inventoryService, cache) {
    this.db = db;
    this.models = models;
    this.access = access;
    this.notifications = notifications;
    this.productsService = productsService;
    this.locationsService = locationsService;
    this.inventoryService = inventoryService;
    this.cache = cache;
  }

  /**
   * `notify: false` is for callers that send their own summary instead (a stock count creates one
   * request per variance but notifies approvers once).
   */
  async createRequest(input, { notify = true } = {}) {
    await this.productsService.assertExists(input.productId);
    // Stock (and therefore stock corrections) only exists at leaf locations — in a warehouse the
    // requester may access.
    await this.locationsService.assertLeaf(input.locationId, input.requestedBy);
    const created = await this.models.insert('stockAdjustment', {
      productId: input.productId,
      locationId: input.locationId,
      bucket: input.bucket,
      delta: input.delta,
      direction: input.direction,
      reason: input.reason,
      reference: input.reference,
      requestedBy: input.requestedBy,
      photoPath: input.photoPath,
      // status defaults to PENDING — this call NEVER touches
      // inventory_balances or inventory_transactions.
    });
    // The pending-adjustments tile on the dashboard just changed.
    await this.cache.invalidate(TAGS.STOCK);
    const adjustment = await this.getExisting(created.id);
    if (notify) this.notifications.adjustmentRequested(adjustment);
    return adjustment;
  }

  async findAll(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    const where = new Where().eq('a.status', query.status).in('l.warehouse_id', scope ?? undefined);
    const rows = await this.db.query(`${ADJUSTMENT_SELECT} ${where.sql} ORDER BY a.requested_at DESC`, where.params);
    return rows.map(nest);
  }

  async getExisting(id) {
    const row = await this.db.one(`${ADJUSTMENT_SELECT} WHERE a.id = ?`, [id]);
    if (!row) throw notFound(`Stock adjustment ${id} not found`);
    return nest(row);
  }

  /** getExisting + the caller must have access to the adjustment's warehouse. */
  async getAccessible(id, userId) {
    const adjustment = await this.getExisting(id);
    await this.access.assertWarehouse(userId, adjustment.location.warehouseId);
    return adjustment;
  }

  /**
   * The ONLY place a stock adjustment ever moves stock. Everything before
   * this point (request, PENDING) has zero ledger effect (rule 2 /
   * Open Decision #2, resolved).
   */
  async approve(id, reviewedBy, reviewNote) {
    const adjustment = await this.getAccessible(id, reviewedBy);
    if (adjustment.status !== 'PENDING') {
      throw conflict(`Stock adjustment ${id} is already ${adjustment.status} and cannot be approved again`);
    }
    // Separation of duties: the requester cannot also be the approver.
    if (reviewedBy === adjustment.requestedBy) {
      throw forbidden('You cannot approve your own adjustment request — a different user must review it');
    }
    const bucket = BUCKET_MAP[adjustment.bucket];
    const isIncrease = adjustment.direction === 'INCREASE';
    // The ledger engine is what actually writes the inventory_transactions row and the
    // inventory_balances delta, atomically, with its own DB-trigger backstop.
    const transaction = await this.inventoryService.applyTransaction({
      type: 'ADJUSTMENT',
      productId: adjustment.productId,
      quantity: Number(adjustment.delta),
      bucket,
      toLocationId: isIncrease ? adjustment.locationId : undefined,
      fromLocationId: isIncrease ? undefined : adjustment.locationId,
      reason: adjustment.reason,
      reference: adjustment.reference ?? undefined,
      performedBy: reviewedBy,
    });
    // NOTE: this update is sequential, not nested inside the same DB
    // transaction as applyTransaction() above — applyTransaction() is
    // self-contained by design. The ledger write (the actual stock movement,
    // and the thing rule 2 cares about) happens first and is atomic on its
    // own; if this bookkeeping update were to fail, the adjustment would
    // remain visibly PENDING despite stock having moved — a recoverable
    // inconsistency, not a ledger integrity violation.
    await this.markReviewed(id, 'APPROVED', reviewedBy, reviewNote);
    await this.cache.invalidate(TAGS.STOCK);
    const approved = await this.getExisting(id);
    this.notifications.adjustmentReviewed(approved);
    return { ...approved, transactionId: transaction.id };
  }

  async reject(id, reviewedBy, reviewNote) {
    const adjustment = await this.getAccessible(id, reviewedBy);
    if (adjustment.status !== 'PENDING') {
      throw conflict(`Stock adjustment ${id} is already ${adjustment.status} and cannot be rejected`);
    }
    await this.markReviewed(id, 'REJECTED', reviewedBy, reviewNote);
    await this.cache.invalidate(TAGS.STOCK);
    const rejected = await this.getExisting(id);
    this.notifications.adjustmentReviewed(rejected);
    return rejected;
  }

  markReviewed(id, status, reviewedBy, reviewNote) {
    return this.db.exec(
      'UPDATE stock_adjustments SET status = ?, reviewed_by = ?, reviewed_at = ?, review_note = ? WHERE id = ?',
      [status, reviewedBy, new Date(), reviewNote ?? null, id],
    );
  }

  /**
   * Reports dashboard — request counts by status over the last [days]
   * (a DB-level GROUP BY), plus the oldest PENDING requests overall (up to
   * 15) so a manager can see what's overdue for review. `oldestPending` is
   * deliberately NOT scoped to [days]: a backlog that's been waiting longer
   * than the period is exactly what "overdue" needs to surface, and
   * `totalPendingCount` (also unscoped) is the true current backlog size.
   */
  async getAdjustmentsSummary(days = 7, warehouseIds = null) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    // `warehouseIds` (null = all) limits every figure to the viewer's warehouses.
    const inScope = (where) => where.in('l.warehouse_id', warehouseIds ?? undefined);
    const period = inScope(new Where().raw('a.requested_at >= ?', since));
    const pending = inScope(new Where().raw("a.status = 'PENDING'"));
    const [grouped, pendingRow, oldestPendingRows] = await Promise.all([
      this.db.query(
        `SELECT a.status, COUNT(*) AS n FROM stock_adjustments a JOIN locations l ON l.id = a.location_id
          ${period.sql} GROUP BY a.status`,
        period.params,
      ),
      this.db.one(
        `SELECT COUNT(*) AS n FROM stock_adjustments a JOIN locations l ON l.id = a.location_id ${pending.sql}`,
        pending.params,
      ),
      this.db.query(`${ADJUSTMENT_SELECT} ${pending.sql} ORDER BY a.requested_at ASC LIMIT 15`, pending.params),
    ]);
    const countByStatus = new Map(grouped.map((g) => [g.status, Number(g.n)]));
    const byStatus = Object.fromEntries(Object.values(AdjustmentStatus).map((status) => [status, countByStatus.get(status) ?? 0]));
    const oldestPending = oldestPendingRows.map(nest).map((a) => ({
      ...a,
      waitingDays: Math.floor((Date.now() - a.requestedAt.getTime()) / (24 * 60 * 60 * 1000)),
    }));
    return { periodDays: days, byStatus, totalPendingCount: Number(pendingRow.n), oldestPending };
  }
}

module.exports = { StockAdjustmentsService };
