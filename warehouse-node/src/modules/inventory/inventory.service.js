'use strict';

const { randomUUID } = require('crypto');
const { badRequest, conflict } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { isUniqueViolation } = require('../../core/db');
const { cols, nest, Where } = require('../../core/models');
const { InventoryTransactionType } = require('../../core/enums');
const { resolveBucketDeltas } = require('./inventory-transaction-effects');

/** Balance bucket (as resolveBucketDeltas names it) -> inventory_balances column. */
const BUCKET_COLUMNS = {
  onHand: 'on_hand',
  reserved: 'reserved',
  damaged: 'damaged',
  lost: 'lost',
  expired: 'expired',
};

/** Balance bucket -> the inventory_units.status a unit takes on when it arrives in that bucket. */
const UNIT_STATUS_BY_BUCKET = {
  onHand: 'ON_HAND',
  reserved: 'RESERVED',
  damaged: 'DAMAGED',
  lost: 'LOST',
  expired: 'EXPIRED',
};

// Phase 1 (receiving) only — see inventory_units in db/schema.sql. Each of these types produces
// exactly one unambiguous "arrival" delta (a positive one) in resolveBucketDeltas' output, which is
// what a unit-tracked transaction needs: the single destination (bucket, location) every scanned
// unit moves to. TRANSFER/ADJUSTMENT/ISSUE/etc. need their own deliberate per-type design (which
// specific on-hand units a DECREASE consumes is not yet decided) — passing unitIds for any type not
// listed here is refused rather than guessed at.
const UNIT_TRACKED_TYPES = new Set(['RECEIVE', 'RETURN']);

// One MariaDB CHECK constraint per bucket (see inventory_balances in
// db/schema.sql) — the database's own backstop against a bucket going negative,
// on top of the DB-write guard trigger. No caller currently pre-validates
// sufficient balance before writing (unlike the external reservation API's
// own "available" check), so this constraint is the ONLY thing stopping an
// over-issue/over-decrement for RECEIVE/ISSUE/TRANSFER/ADJUSTMENT/DAMAGED/
// LOST alike — every one of them can hit this.
const NONNEG_CONSTRAINT_BUCKETS = {
  inventory_balances_on_hand_nonneg: 'onHand',
  inventory_balances_reserved_nonneg: 'reserved',
  inventory_balances_damaged_nonneg: 'damaged',
  inventory_balances_lost_nonneg: 'lost',
  inventory_balances_expired_nonneg: 'expired',
};
const BUCKET_LABELS = {
  onHand: 'on-hand',
  reserved: 'reserved',
  damaged: 'damaged',
  lost: 'lost',
  expired: 'expired',
};

/**
 * Translates the raw MariaDB/MySQL error from a `..._nonneg` CHECK constraint violation into a
 * clean, human 409 — instead of letting the driver error (constraint name, SQLSTATE, raw SQL) leak
 * into the API response as a 500. Never returns; rethrows anything that isn't one of these.
 */
function translateBalanceConstraintViolation(error) {
  const message = error instanceof Error ? error.message : String(error);
  for (const [constraint, bucket] of Object.entries(NONNEG_CONSTRAINT_BUCKETS)) {
    if (message.includes(constraint)) {
      throw conflict(`This would take the ${BUCKET_LABELS[bucket]} quantity below zero at this location — there isn't enough stock there to do this.`);
    }
  }
  throw error;
}

// The ledger row plus the { id, sku, name } / { id, name, code } summaries every ledger view shows.
const TRANSACTION_SELECT = `
  SELECT ${cols('inventoryTransaction', 't')},
         ${cols('product', 'p', ['id', 'sku', 'name'], 'product.')},
         ${cols('location', 'fl', ['id', 'name', 'code'], 'fromLocation.')},
         ${cols('location', 'tl', ['id', 'name', 'code'], 'toLocation.')},
         ${cols('user', 'u', ['id', 'fullName'], 'performedByUser.')}
    FROM inventory_transactions t
    JOIN products p ON p.id = t.product_id
    LEFT JOIN locations fl ON fl.id = t.from_location_id
    LEFT JOIN locations tl ON tl.id = t.to_location_id
    LEFT JOIN users u ON u.id = t.performed_by`;

/**
 * Report scoping. `warehouseIds` is the viewer's warehouse scope (modules/access): null = every
 * warehouse, otherwise a NON-EMPTY list (callers return an empty report for an empty scope, since
 * `IN ()` is not valid SQL). Returns SQL fragments plus their parameters, in order of appearance.
 */
function reportScope(warehouseIds) {
  const scoped = warehouseIds !== null && warehouseIds !== undefined;
  return {
    // Per-product on_hand over ACTIVE locations in scope (every balance row is already at a leaf).
    onHandByProduct: `
      SELECT ib.product_id, SUM(ib.on_hand) AS total_on_hand
        FROM inventory_balances ib
       INNER JOIN locations l ON l.id = ib.location_id AND l.is_active = 1
       ${scoped ? 'WHERE l.warehouse_id IN (?)' : ''}
       GROUP BY ib.product_id`,
    // Products whose catalogue (category -> workstream) lives in a warehouse in scope.
    productJoin: scoped
      ? 'JOIN categories c ON c.id = p.category_id JOIN workstreams w ON w.id = c.workstream_id AND w.warehouse_id IN (?)'
      : '',
    // A ledger row is in scope if either end is a location in scope.
    transactionFilter: scoped ? '(fl.warehouse_id IN (?) OR tl.warehouse_id IN (?))' : '',
    params: (n) => (scoped ? Array(n).fill(warehouseIds) : []),
    empty: scoped && warehouseIds.length === 0,
  };
}

/**
 * Owns inventory_balances and inventory_transactions. This is the ONLY
 * service in the codebase permitted to write inventory_balances (rule 2) —
 * every other module (receiving, transfers, counts, the external stock API)
 * must call applyTransaction() rather than touching that table directly.
 * A DB trigger (see the end of db/schema.sql) backstops this
 * at the database level too.
 */
class InventoryService {
  constructor({ db, models, access }, productsService, locationsService, cache) {
    this.db = db;
    this.access = access;
    this.models = models;
    this.productsService = productsService;
    this.locationsService = locationsService;
    this.cache = cache;
  }

  /**
   * Writes one inventory_transactions row (the truth) and the resulting
   * inventory_balances delta(s) (the cache) in a single DB transaction
   * (§H). Both commit or both roll back together.
   */
  async applyTransaction(input) {
    // A unit-tracked call's quantity is never trusted from the caller — it IS the unit count, always
    // recomputed here, which is what structurally stops "type a number" for a SERIAL product
    // (the scanning UI never even shows a quantity field for one, but this is the real backstop).
    if (input.unitIds?.length) {
      if (!UNIT_TRACKED_TYPES.has(input.type)) {
        throw badRequest(`Unit-tracked quantities are not supported for ${input.type} yet`);
      }
      input = { ...input, quantity: input.unitIds.length };
    }
    if (!Number.isFinite(input.quantity) || input.quantity <= 0) {
      throw badRequest('quantity must be a positive number');
    }
    // Cheap existence check (the full getExisting also runs the stock aggregate — pointless here).
    await this.productsService.assertExists(input.productId);
    const locationIds = [input.fromLocationId, input.toLocationId].filter((id) => Boolean(id));
    for (const locationId of locationIds) {
      await this.locationsService.getExisting(locationId);
    }
    const deltas = resolveBucketDeltas(input);

    const result = await this.db.transaction(async (tx) => {
      // Lifts the DB trigger's write guard for this transaction. MySQL/MariaDB
      // session variables are connection-scoped and survive both COMMIT and
      // ROLLBACK, so it is cleared again in `finally` before this dedicated
      // connection goes back to the pool — otherwise a later unrelated query
      // reusing that connection would inherit the flag.
      await this.db.exec('SET @allow_balance_write = 1', [], tx);
      try {
        const transaction = await this.models.insert(
          'inventoryTransaction',
          {
            type: input.type,
            productId: input.productId,
            fromLocationId: input.fromLocationId ?? null,
            toLocationId: input.toLocationId ?? null,
            quantity: input.quantity,
            reason: input.reason,
            reference: input.reference,
            orderId: input.orderId,
            performedBy: input.performedBy,
          },
          tx,
        );
        for (const delta of deltas) {
          await this.applyBalanceDelta(tx, input.productId, delta);
        }
        if (input.unitIds?.length) {
          await this.applyUnitMoves(tx, transaction.id, input.unitIds, deltas);
        }
        return transaction;
      } finally {
        await this.db.exec('SET @allow_balance_write = NULL', [], tx);
      }
    });

    // Committed: everything derived from the ledger (product totals, dashboards, reports) is now stale.
    await this.cache.invalidate(TAGS.STOCK);
    return result;
  }

  /**
   * Moves every scanned unit to wherever this transaction's stock actually arrived, and records the
   * link (rule 2's append-only ledger, extended to unit granularity). `deltas` always has exactly one
   * positive ("arrival") entry for the types in UNIT_TRACKED_TYPES — that's the destination every
   * unit takes on.
   */
  async applyUnitMoves(tx, transactionId, unitIds, deltas) {
    const arrival = deltas.find((d) => d.delta > 0);
    const status = UNIT_STATUS_BY_BUCKET[arrival.bucket];
    await this.db.exec(
      `UPDATE inventory_units SET status = ?, location_id = ?, updated_at = ? WHERE id IN (?)`,
      [status, arrival.locationId, new Date(), unitIds],
      tx,
    );
    await this.models.insertMany(
      'inventoryTransactionUnit',
      unitIds.map((unitId) => ({ transactionId, unitId })),
      tx,
    );
  }

  /**
   * Pre-prints N unique labels for a SERIAL product, ahead of it physically arriving — each becomes
   * a PENDING inventory_units row (unit_code = its own id, so the printed `WH:U:<id>` label IS the
   * lookup key) that `resolveUnitsForReceive` picks up the first time it's scanned in.
   */
  async generateUnits(productId, count) {
    const product = await this.productsService.getExisting(productId);
    if (product.trackingMode !== 'SERIAL') {
      throw badRequest('Only SERIAL-tracked products can have unit labels generated');
    }
    if (!Number.isInteger(count) || count < 1 || count > 500) {
      throw badRequest('count must be a whole number between 1 and 500');
    }
    const rows = Array.from({ length: count }, () => {
      const id = randomUUID();
      return { id, productId, unitCode: id, source: 'GENERATED' };
    });
    await this.models.insertMany('inventoryUnit', rows);
    return rows.map((r) => r.id);
  }

  /**
   * Turns the codes scanned for a SERIAL receiving line into unitIds ready for applyTransaction —
   * the one place that decides whether a scanned code is a pre-printed label coming in for the first
   * time, a brand-new supplier barcode, or a code that can't be received (already received elsewhere,
   * or printed for a different product). Throws a 409 naming every bad code at once (extra.rejectedCodes)
   * so the caller can report exactly which scans to drop and retry, rather than stopping at the first one.
   */
  async resolveUnitsForReceive(productId, unitCodes) {
    const codes = [...new Set(unitCodes)];
    const existing = codes.length
      ? await this.db.query(
          'SELECT id, unit_code AS unitCode, product_id AS productId, status FROM inventory_units WHERE unit_code IN (?)',
          [codes],
        )
      : [];
    const byCode = new Map(existing.map((u) => [u.unitCode, u]));
    const unitIds = [];
    const toCreate = [];
    const rejected = [];
    for (const code of codes) {
      const found = byCode.get(code);
      if (!found) {
        toCreate.push(code);
      } else if (found.productId !== productId) {
        rejected.push({ code, reason: 'This code is registered to a different product' });
      } else if (found.status !== 'PENDING') {
        rejected.push({ code, reason: found.status === 'ON_HAND' ? 'Already received' : `Not available (${found.status.toLowerCase()})` });
      } else {
        unitIds.push(found.id);
      }
    }
    if (rejected.length) {
      throw conflict(
        `${rejected.length} scanned code${rejected.length === 1 ? '' : 's'} can't be received: ${rejected.map((r) => `${r.code} — ${r.reason}`).join('; ')}`,
        { rejectedCodes: rejected },
      );
    }
    if (toCreate.length) {
      const created = toCreate.map((code) => ({ id: randomUUID(), productId, unitCode: code, source: 'SUPPLIER' }));
      await this.models.insertMany('inventoryUnit', created);
      unitIds.push(...created.map((c) => c.id));
    }
    return unitIds;
  }

  /**
   * Deliberately NOT `INSERT ... ON DUPLICATE KEY UPDATE`: the CHECK constraints must be evaluated
   * against the real post-increment row, and a negative delta (e.g. TRANSFER's -30 leg) must never
   * be judged as a fresh row's starting value. Explicit update-then-insert gets both cases right.
   */
  async applyBalanceDelta(tx, productId, delta) {
    const column = BUCKET_COLUMNS[delta.bucket];
    const increment = () =>
      this.db.exec(
        `UPDATE inventory_balances SET \`${column}\` = \`${column}\` + ? WHERE product_id = ? AND location_id = ?`,
        [delta.delta, productId, delta.locationId],
        tx,
      );

    try {
      const updated = await increment();
      if (updated.affectedRows > 0) return;
      try {
        // First stock of this product at this location: every bucket starts at 0 except the one moving.
        const buckets = Object.keys(BUCKET_COLUMNS).map((bucket) => (bucket === delta.bucket ? delta.delta : 0));
        await this.db.exec(
          `INSERT INTO inventory_balances (id, product_id, location_id, on_hand, reserved, damaged, lost, expired)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [randomUUID(), productId, delta.locationId, ...buckets],
          tx,
        );
      } catch (error) {
        // Lost a race with a concurrent first-write for the same (product, location) between the
        // UPDATE above and this INSERT — the row exists now, so retry as an update.
        if (isUniqueViolation(error)) {
          await increment();
          return;
        }
        throw error;
      }
    } catch (error) {
      // Any of the three writes above can hit a `..._nonneg` CHECK constraint — translate it into a
      // clean error instead of leaking the raw one.
      translateBalanceConstraintViolation(error);
    }
  }

  /** Balance and ledger views are limited to locations in the viewer's warehouses (modules/access). */
  async findBalances(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    const where = new Where()
      .in('l.warehouse_id', scope ?? undefined)
      .eq('ib.product_id', query.productId)
      .eq('ib.location_id', query.locationId)
      .eq('l.warehouse_id', query.warehouseId);
    const rows = await this.db.query(
      `SELECT ${cols('inventoryBalance', 'ib')},
              ${cols('product', 'p', ['id', 'sku', 'name', 'uom'], 'product.')},
              ${cols('location', 'l', ['id', 'name', 'code', 'warehouseId'], 'location.')},
              (ib.on_hand - ib.reserved) AS available
         FROM inventory_balances ib
         JOIN products p ON p.id = ib.product_id
         JOIN locations l ON l.id = ib.location_id
         ${where.sql}
        ORDER BY ib.product_id ASC, ib.location_id ASC`,
      where.params,
    );
    return rows.map(nest);
  }

  async findTransactions(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    if (scope !== null && scope.length === 0) return [];
    const where = new Where().eq('t.product_id', query.productId).eq('t.type', query.type);
    if (scope !== null) where.raw('(fl.warehouse_id IN (?) OR tl.warehouse_id IN (?))', scope, scope);
    if (query.locationId) where.raw('(t.from_location_id = ? OR t.to_location_id = ?)', query.locationId, query.locationId);
    if (query.from) where.raw('t.created_at >= ?', new Date(query.from));
    if (query.to) where.raw('t.created_at <= ?', new Date(query.to));
    const limit = query.limit ? ` LIMIT ${Number(query.limit)}` : '';
    const rows = await this.db.query(`${TRANSACTION_SELECT} ${where.sql} ORDER BY t.created_at DESC${limit}`, where.params);
    return rows.map(nest);
  }

  /**
   * One SERIAL product's units, paginated, newest first — every physical unit's own code, status
   * and current location (null while PENDING or after ISSUED). Scoped by the PRODUCT's warehouse
   * (via its category -> workstream), not the unit's own location, since a unit can legitimately
   * have no location (unlike a balance row, which always has one).
   */
  async findUnits(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    if (scope !== null && scope.length === 0) return { data: [], page: 1, pageSize: query.pageSize ?? 20, total: 0, totalPages: 0 };
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const where = new Where().eq('iu.product_id', query.productId).eq('iu.status', query.status);
    if (scope !== null) where.raw('w.warehouse_id IN (?)', scope);
    const joinScope = 'JOIN categories c ON c.id = p.category_id JOIN workstreams w ON w.id = c.workstream_id';
    const [countRow, rows] = await Promise.all([
      this.db.one(`SELECT COUNT(*) AS total FROM inventory_units iu JOIN products p ON p.id = iu.product_id ${joinScope} ${where.sql}`, where.params),
      this.db.query(
        `SELECT ${cols('inventoryUnit', 'iu')},
                ${cols('location', 'l', ['id', 'name', 'code', 'warehouseId'], 'location.')}
           FROM inventory_units iu
           JOIN products p ON p.id = iu.product_id
           ${joinScope}
           LEFT JOIN locations l ON l.id = iu.location_id
           ${where.sql}
          ORDER BY iu.created_at DESC
          LIMIT ? OFFSET ?`,
        [...where.params, pageSize, (page - 1) * pageSize],
      ),
    ]);
    const total = Number(countRow.total);
    return { data: rows.map(nest), page, pageSize, total, totalPages: Math.ceil(total / pageSize) || 0 };
  }

  /**
   * Reports dashboard — every ACTIVE product whose total on-hand across
   * ACTIVE leaf locations is below its min_stock_level, ordered worst-short
   * first. The inner subquery aggregates on_hand PER PRODUCT in SQL (a LEFT
   * JOIN so a product with zero balance rows still gets a 0 — a product with
   * no stock anywhere and a positive min level correctly counts as low stock).
   * The comparison happens in SQL — no full-table fetch, no summing in JS.
   */
  async getLowStockProducts(warehouseIds = null) {
    const scope = reportScope(warehouseIds);
    if (scope.empty) return [];
    const rows = await this.db.query(
      `
      SELECT x.id, x.sku, x.name, x.min_stock_level AS minStockLevel, x.on_hand AS onHand
      FROM (
        SELECT p.id, p.sku, p.name, p.min_stock_level,
               COALESCE(s.total_on_hand, 0) AS on_hand
        FROM products p
        ${scope.productJoin}
        LEFT JOIN (${scope.onHandByProduct}) s ON s.product_id = p.id
        WHERE p.status = 'ACTIVE'
      ) x
      WHERE x.on_hand < x.min_stock_level
      ORDER BY (x.min_stock_level - x.on_hand) DESC, x.sku ASC
    `,
      scope.params(2),
    );
    return rows.map((r) => {
      const onHand = Number(r.onHand);
      const minStockLevel = Number(r.minStockLevel);
      return {
        productId: r.id,
        sku: r.sku,
        name: r.name,
        onHand,
        minStockLevel,
        shortfall: minStockLevel - onHand,
      };
    });
  }

  /**
   * Reports dashboard — total value of on-hand stock (ACTIVE products only,
   * cost_price required) plus the 5 highest-value products. Products with a
   * null cost_price are excluded from the total (never treated as 0) and
   * counted separately so the dashboard can disclose the gap honestly.
   * Both the total and the top-5 ranking are computed in SQL.
   */
  async getInventoryValuation(warehouseIds = null) {
    const scope = reportScope(warehouseIds);
    if (scope.empty) return { total: 0, excludedProductCount: 0, topProducts: [] };
    const productBalances = `
      SELECT p.id, p.sku, p.name, p.cost_price, COALESCE(s.total_on_hand, 0) AS on_hand
      FROM products p
      ${scope.productJoin}
      LEFT JOIN (${scope.onHandByProduct}) s ON s.product_id = p.id
      WHERE p.status = 'ACTIVE' AND p.cost_price IS NOT NULL
    `;
    const [totalRow, topRows, excludedRow] = await Promise.all([
      this.db.one(`SELECT SUM(x.on_hand * x.cost_price) AS total FROM (${productBalances}) x`, scope.params(2)),
      this.db.query(
        `
        SELECT x.id, x.sku, x.name, x.on_hand AS onHand, x.cost_price AS costPrice,
               (x.on_hand * x.cost_price) AS value
        FROM (${productBalances}) x
        ORDER BY value DESC, x.sku ASC
        LIMIT 5
      `,
        scope.params(2),
      ),
      this.db.one(
        `SELECT COUNT(*) AS n FROM products p ${scope.productJoin} WHERE p.status = 'ACTIVE' AND p.cost_price IS NULL`,
        scope.params(1),
      ),
    ]);
    return {
      total: Number(totalRow?.total ?? 0),
      excludedProductCount: Number(excludedRow.n),
      topProducts: topRows.map((r) => ({
        productId: r.id,
        sku: r.sku,
        name: r.name,
        onHand: Number(r.onHand),
        costPrice: Number(r.costPrice),
        value: Number(r.value),
      })),
    };
  }

  /**
   * Reports dashboard — transaction counts by type over the last [days]
   * (a DB-level GROUP BY), plus the most recent 15 transactions overall as a
   * "recent activity" feed. The feed is deliberately NOT scoped to [days]: a
   * quiet week would leave it empty and defeat its purpose, unlike the period
   * counts which measure throughput.
   */
  async getStockMovementSummary(days = 7, warehouseIds = null) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const scope = reportScope(warehouseIds);
    const emptyByType = () => Object.fromEntries(Object.values(InventoryTransactionType).map((type) => [type, 0]));
    if (scope.empty) return { periodDays: days, byType: emptyByType(), recentActivity: [] };
    const scopeAnd = scope.transactionFilter ? `AND ${scope.transactionFilter}` : '';
    const scopeWhere = scope.transactionFilter ? `WHERE ${scope.transactionFilter}` : '';
    const [grouped, recentRows] = await Promise.all([
      this.db.query(
        `SELECT t.type, COUNT(*) AS n FROM inventory_transactions t
           LEFT JOIN locations fl ON fl.id = t.from_location_id
           LEFT JOIN locations tl ON tl.id = t.to_location_id
          WHERE t.created_at >= ? ${scopeAnd}
          GROUP BY t.type`,
        [since, ...scope.params(2)],
      ),
      this.db.query(
        `SELECT ${cols('inventoryTransaction', 't')},
                ${cols('product', 'p', ['id', 'sku', 'name'], 'product.')},
                ${cols('location', 'fl', ['id', 'name', 'code'], 'fromLocation.')},
                ${cols('location', 'tl', ['id', 'name', 'code'], 'toLocation.')},
                ${cols('user', 'u', ['id', 'fullName', 'email'], 'performedByUser.')}
           FROM inventory_transactions t
           JOIN products p ON p.id = t.product_id
           LEFT JOIN locations fl ON fl.id = t.from_location_id
           LEFT JOIN locations tl ON tl.id = t.to_location_id
           JOIN users u ON u.id = t.performed_by
          ${scopeWhere}
          ORDER BY t.created_at DESC
          LIMIT 15`,
        scope.params(2),
      ),
    ]);
    const countByType = new Map(grouped.map((g) => [g.type, Number(g.n)]));
    const byType = Object.fromEntries(Object.values(InventoryTransactionType).map((type) => [type, countByType.get(type) ?? 0]));
    return { periodDays: days, byType, recentActivity: recentRows.map(nest) };
  }
}

module.exports = { InventoryService };
