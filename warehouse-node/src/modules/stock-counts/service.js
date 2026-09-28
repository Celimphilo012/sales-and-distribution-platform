'use strict';

const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, nest, groupBy, Where } = require('../../core/models');

const COUNT_SELECT = `
  SELECT ${cols('stockCount', 's')},
         ${cols('location', 'l', ['id', 'name', 'code', 'warehouseId'], 'location.')},
         ${cols('user', 'u', ['id', 'fullName', 'email'], 'startedByUser.')}
    FROM stock_counts s
    JOIN locations l ON l.id = s.location_id
    JOIN users u ON u.id = s.started_by`;

class StockCountsService {
  constructor({ db, models, access, notifications }, productsService, locationsService, stockAdjustmentsService, cache) {
    this.db = db;
    this.models = models;
    this.access = access;
    this.notifications = notifications;
    this.productsService = productsService;
    this.locationsService = locationsService;
    this.stockAdjustmentsService = stockAdjustmentsService;
    this.cache = cache;
  }

  /** Attaches items (each with its product { id, sku, name }) to each count — one query for the list. */
  async withItems(counts) {
    if (counts.length === 0) return counts;
    const rows = await this.db.query(
      `SELECT ${cols('stockCountItem', 'i')}, ${cols('product', 'p', ['id', 'sku', 'name'], 'product.')}
         FROM stock_count_items i
         JOIN products p ON p.id = i.product_id
        WHERE i.stock_count_id IN (?)`,
      [counts.map((c) => c.id)],
    );
    const byCount = groupBy(rows.map(nest), 'stockCountId');
    return counts.map((c) => ({ ...c, items: byCount.get(c.id) ?? [] }));
  }

  /**
   * Starts a count: snapshots expected_qty (current on_hand) for every
   * targeted product at this location. Read-only against inventory —
   * nothing here touches inventory_balances or inventory_transactions.
   */
  async create(dto, startedBy) {
    const location = await this.locationsService.assertLeaf(dto.locationId, startedBy);
    const targets = dto.productIds
      ? await this.snapshotExplicitProducts(dto.productIds, dto.locationId)
      : await this.snapshotAllBalancesAt(dto.locationId);
    if (targets.length === 0) {
      throw badRequest('Nothing to count: no products specified and no existing inventory balances at this location');
    }
    const countId = await this.db.transaction(async (tx) => {
      const created = await this.models.insert(
        'stockCount',
        { warehouseId: location.warehouseId, locationId: dto.locationId, startedBy },
        tx,
      );
      await this.models.insertMany(
        'stockCountItem',
        targets.map((t) => ({
          stockCountId: created.id,
          productId: t.productId,
          locationId: dto.locationId,
          expectedQty: t.expectedQty,
        })),
        tx,
      );
      return created.id;
    });
    await this.cache.invalidate(TAGS.STOCK); // the dashboard's "open stock counts" tile
    return this.getExisting(countId);
  }

  async findAll(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    const where = new Where()
      .eq('s.status', query.status)
      .eq('s.location_id', query.locationId)
      .in('s.warehouse_id', scope ?? undefined);
    const rows = await this.db.query(`${COUNT_SELECT} ${where.sql} ORDER BY s.started_at DESC`, where.params);
    return this.withItems(rows.map(nest));
  }

  async getExisting(id) {
    const row = await this.db.one(`${COUNT_SELECT} WHERE s.id = ?`, [id]);
    if (!row) throw notFound(`Stock count ${id} not found`);
    const [count] = await this.withItems([nest(row)]);
    return count;
  }

  /** getExisting + the caller must have access to the count's warehouse. */
  async getAccessible(id, userId) {
    const count = await this.getExisting(id);
    await this.access.assertWarehouse(userId, count.warehouseId);
    return count;
  }

  /** DB-level COUNT for the reports dashboard's "open stock counts" tile, within the given warehouses. */
  async countOpen(warehouseIds = null) {
    const where = new Where().raw("status = 'OPEN'").in('warehouse_id', warehouseIds ?? undefined);
    return Number((await this.db.one(`SELECT COUNT(*) AS n FROM stock_counts ${where.sql}`, where.params)).n);
  }

  /**
   * Submits counted quantities, computes the difference per item, and
   * records the variance. Stock does NOT move here — a nonzero difference
   * only creates a PENDING StockAdjustment (rule 2 stays intact: the count
   * itself never calls InventoryService.applyTransaction()). A manager
   * applying those adjustments through the approve flow is what actually
   * authorizes and moves stock.
   */
  async submit(id, dto, submittedBy) {
    const count = await this.getAccessible(id, submittedBy);
    if (count.status !== 'OPEN') {
      throw conflict(`Stock count ${id} is already ${count.status} and cannot be resubmitted`);
    }
    const expectedProductIds = new Set(count.items.map((i) => i.productId));
    const submittedProductIds = new Set(dto.items.map((i) => i.productId));
    const missing = [...expectedProductIds].filter((p) => !submittedProductIds.has(p));
    const extra = [...submittedProductIds].filter((p) => !expectedProductIds.has(p));
    if (missing.length > 0 || extra.length > 0) {
      throw badRequest(
        `Submitted items must exactly match the counted products.` +
          (missing.length ? ` Missing: ${missing.join(', ')}.` : '') +
          (extra.length ? ` Not part of this count: ${extra.join(', ')}.` : ''),
      );
    }
    const itemByProduct = new Map(count.items.map((i) => [i.productId, i]));
    const results = dto.items.map((submitted) => {
      const item = itemByProduct.get(submitted.productId);
      const difference = submitted.countedQty - Number(item.expectedQty);
      return { itemId: item.id, productId: submitted.productId, countedQty: submitted.countedQty, difference };
    });

    // Records the variance — this transaction only ever touches
    // stock_count_items/stock_counts, never inventory_balances.
    await this.db.transaction(async (tx) => {
      for (const r of results) {
        await this.db.exec('UPDATE stock_count_items SET counted_qty = ?, difference = ? WHERE id = ?', [r.countedQty, r.difference, r.itemId], tx);
      }
      await this.db.exec("UPDATE stock_counts SET status = 'SUBMITTED', submitted_at = ? WHERE id = ?", [new Date(), id], tx);
    });

    // Approval is the authorization: each nonzero variance becomes a
    // PENDING request through the exact same path (and the exact same
    // leaf-location check) as a manually-requested adjustment.
    const createdAdjustmentIds = [];
    for (const r of results) {
      if (r.difference === 0) continue;
      const adjustment = await this.stockAdjustmentsService.createRequest(
        {
          productId: r.productId,
          locationId: count.locationId,
          bucket: 'ON_HAND',
          delta: Math.abs(r.difference),
          direction: r.difference > 0 ? 'INCREASE' : 'DECREASE',
          reason: 'stock count',
          reference: count.id,
          requestedBy: submittedBy,
        },
        { notify: false }, // approvers get one summary below instead
      );
      createdAdjustmentIds.push(adjustment.id);
    }
    await this.cache.invalidate(TAGS.STOCK);
    const submitter = await this.db.one('SELECT id, full_name AS fullName FROM users WHERE id = ?', [submittedBy]);
    this.notifications.stockCountSubmitted(count, submitter, createdAdjustmentIds.length);
    return { ...(await this.getExisting(id)), createdAdjustmentIds };
  }

  async snapshotExplicitProducts(productIds, locationId) {
    // One query for the whole list (was one full getExisting per product).
    await this.productsService.assertAllExist(productIds);
    const balances = await this.db.query(
      'SELECT product_id AS productId, on_hand AS onHand FROM inventory_balances WHERE location_id = ? AND product_id IN (?)',
      [locationId, productIds],
    );
    const balanceByProduct = new Map(balances.map((b) => [b.productId, b.onHand]));
    return productIds.map((productId) => ({
      productId,
      expectedQty: balanceByProduct.get(productId) ?? 0,
    }));
  }

  async snapshotAllBalancesAt(locationId) {
    const balances = await this.db.query(
      'SELECT product_id AS productId, on_hand AS onHand FROM inventory_balances WHERE location_id = ?',
      [locationId],
    );
    return balances.map((b) => ({ productId: b.productId, expectedQty: b.onHand }));
  }
}

module.exports = { StockCountsService };
