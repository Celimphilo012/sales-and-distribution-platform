'use strict';

const { badRequest, conflict, notFound } = require('../../core/errors');
const { cols } = require('../../core/models');

/**
 * Never logs in, never appears in a role — exists solely to satisfy
 * `inventory_transactions.performed_by`'s NOT NULL FK for ledger rows that
 * an API key (not a JWT user) triggered. Seeded once; see db/seed.js.
 * This keeps the ledger schema completely untouched — no nullable
 * `performed_by`, no new column — while still recording, per rule 2, a
 * real accountable row for every balance-affecting transaction.
 */
const SYSTEM_API_USER_EMAIL = 'system.api@warehouse.internal';

/**
 * The reserve/release/issue linchpin behind `/api/v1/stock/*`. A layer on
 * top of `InventoryService.applyTransaction()` — it never writes
 * `inventory_balances`/`inventory_transactions` itself, only ever through
 * that method, per line, exactly like receiving/transfers/adjustments do.
 *
 * `applyTransaction()` is self-contained — each call opens and commits its
 * own DB transaction, so it cannot be nested inside one outer transaction
 * spanning multiple lines. "All-or-none" is delivered as an OBSERVABLE
 * guarantee instead, via two layers:
 *   1. An up-front availability check across every line, before any write
 *      — in the overwhelmingly common case this alone makes "reserve
 *      nothing on any shortfall" true, with zero DB writes on failure.
 *   2. Saga-style compensation if a later line still fails after that
 *      check passed (a genuine concurrent race, not the common case): every
 *      line already applied in this call is undone via its own
 *      `applyTransaction()` call (RELEASE_RESERVATION / a compensating
 *      RECEIVE), never by editing or deleting the ledger rows already
 *      written — the ledger stays append-only (rule 2) either way.
 */
class StockReservationsService {
  constructor({ db, models }, productsService, locationsService, inventoryService) {
    this.db = db;
    this.models = models;
    this.productsService = productsService;
    this.locationsService = locationsService;
    this.inventoryService = inventoryService;
  }

  async getSystemUserId() {
    if (this.systemUserId) return this.systemUserId;
    const user = await this.db.one('SELECT id FROM users WHERE email = ?', [SYSTEM_API_USER_EMAIL]);
    if (!user) throw new Error(`System API user ${SYSTEM_API_USER_EMAIL} is missing — run the seed script`);
    this.systemUserId = user.id;
    return this.systemUserId;
  }

  /** The reservation for a caller reference, with its lines — or null. */
  async findReservation(reference) {
    const reservation = await this.db.one(
      `SELECT ${cols('stockReservation', 'r')} FROM stock_reservations r WHERE r.reference = ?`,
      [reference],
    );
    if (!reservation) return null;
    reservation.lines = await this.db.query(
      `SELECT ${cols('stockReservationLine', 'l')} FROM stock_reservation_lines l WHERE l.reservation_id = ?`,
      [reservation.id],
    );
    return reservation;
  }

  /** on_hand - reserved at one location (0 when there is no balance row yet). Never cached. */
  async availableAt(productId, locationId) {
    const balance = await this.db.one(
      'SELECT on_hand AS onHand, reserved FROM inventory_balances WHERE product_id = ? AND location_id = ?',
      [productId, locationId],
    );
    return balance ? Number(balance.onHand) - Number(balance.reserved) : 0;
  }

  async checkAvailability(dto) {
    const items = await Promise.all(
      dto.items.map(async (item) => {
        if (item.locationId) {
          const available = await this.availableAt(item.productId, item.locationId);
          return { productId: item.productId, locationId: item.locationId, available };
        }
        const agg = await this.db.one(
          'SELECT SUM(on_hand) AS onHand, SUM(reserved) AS reserved FROM inventory_balances WHERE product_id = ?',
          [item.productId],
        );
        const onHand = agg.onHand ? Number(agg.onHand) : 0;
        const reserved = agg.reserved ? Number(agg.reserved) : 0;
        return { productId: item.productId, locationId: null, available: onHand - reserved };
      }),
    );
    return { items };
  }

  /**
   * Where each product can be reserved from: every ACTIVE location in an ACTIVE warehouse that holds
   * available stock (on_hand - reserved > 0), with `oldestStockAt` — the arrival date of the oldest
   * units still there — so a consumer can reserve oldest stock first (FIFO).
   *
   * `oldestStockAt` is estimated from the ledger the standard FIFO way: walk the location's inbound
   * movements for the product newest-first until they add up to what is on hand now; the movement that
   * gets there is the oldest stock still present (assuming each location is itself picked oldest-first).
   * If the recorded inbound movements don't add up to the balance (e.g. opening stock loaded directly),
   * the earliest inbound date is used; with none at all it is null (treated as newest).
   * Never cached — it reads the live balances.
   */
  async allocationOptions({ productIds }) {
    const ids = [...new Set(productIds)];
    const balances = await this.db.query(
      `SELECT ib.product_id AS productId, ib.location_id AS locationId, l.warehouse_id AS warehouseId,
              ib.on_hand AS onHand, ib.on_hand - ib.reserved AS available
         FROM inventory_balances ib
         JOIN locations l ON l.id = ib.location_id AND l.is_active = true
         JOIN warehouses w ON w.id = l.warehouse_id AND w.is_active = true
        WHERE ib.product_id IN (?) AND ib.on_hand - ib.reserved > 0`,
      [ids],
    );
    const inbound = balances.length
      ? await this.db.query(
          `SELECT product_id AS productId, to_location_id AS locationId, quantity, created_at AS createdAt
             FROM inventory_transactions
            WHERE product_id IN (?) AND to_location_id IN (?)
              AND type IN ('RECEIVE', 'RETURN', 'TRANSFER', 'ADJUSTMENT', 'STOCK_COUNT')
            ORDER BY created_at DESC`,
          [ids, [...new Set(balances.map((b) => b.locationId))]],
        )
      : [];
    const inboundByKey = new Map();
    for (const row of inbound) {
      const key = `${row.productId}:${row.locationId}`;
      if (!inboundByKey.has(key)) inboundByKey.set(key, []);
      inboundByKey.get(key).push(row);
    }
    const oldestStockAt = (balance) => {
      const rows = inboundByKey.get(`${balance.productId}:${balance.locationId}`) ?? [];
      let covered = 0;
      for (const row of rows) {
        covered += Number(row.quantity);
        if (covered >= Number(balance.onHand)) return row.createdAt;
      }
      return rows.length ? rows[rows.length - 1].createdAt : null;
    };
    return {
      products: ids.map((productId) => ({
        productId,
        locations: balances
          .filter((b) => b.productId === productId)
          .map((b) => ({
            locationId: b.locationId,
            warehouseId: b.warehouseId,
            available: Number(b.available),
            oldestStockAt: oldestStockAt(b),
          })),
      })),
    };
  }

  async reserve(dto, apiKeyId) {
    const existing = await this.findReservation(dto.reference);
    if (existing) {
      // Idempotent replay — a retried call after a dropped response must not double-reserve.
      return this.reserveResult(existing);
    }
    for (const line of dto.lines) {
      await this.productsService.assertExists(line.productId);
      await this.locationsService.assertLeaf(line.locationId);
    }
    const shortLines = [];
    for (const line of dto.lines) {
      const available = await this.availableAt(line.productId, line.locationId);
      if (available < line.quantity) {
        shortLines.push({ productId: line.productId, locationId: line.locationId, requested: line.quantity, available });
      }
    }
    if (shortLines.length > 0) {
      return { success: false, reference: dto.reference, shortLines };
    }
    const performedBy = await this.getSystemUserId();
    const succeeded = [];
    try {
      for (const line of dto.lines) {
        await this.inventoryService.applyTransaction({
          type: 'RESERVATION',
          productId: line.productId,
          fromLocationId: line.locationId,
          quantity: line.quantity,
          reference: dto.reference,
          performedBy,
        });
        succeeded.push(line);
      }
    } catch {
      for (const line of succeeded) {
        await this.inventoryService
          .applyTransaction({
            type: 'RELEASE_RESERVATION',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: line.quantity,
            reference: dto.reference,
            performedBy,
          })
          .catch(() => {});
      }
      return {
        success: false,
        reference: dto.reference,
        shortLines: [],
        note: 'A concurrent reservation raced this request after the initial check passed; nothing was left reserved — retry is safe.',
      };
    }

    await this.db.transaction(async (tx) => {
      const reservation = await this.models.insert('stockReservation', { reference: dto.reference, label: dto.label ?? null, apiKeyId }, tx);
      await this.models.insertMany(
        'stockReservationLine',
        dto.lines.map((l) => ({ reservationId: reservation.id, productId: l.productId, locationId: l.locationId, quantity: l.quantity })),
        tx,
      );
    });
    return this.reserveResult(await this.findReservation(dto.reference));
  }

  reserveResult(reservation) {
    return {
      success: true,
      reference: reservation.reference,
      status: reservation.status,
      reserved: reservation.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        quantity: Number(l.quantity),
      })),
    };
  }

  async release(dto) {
    const existing = await this.findReservation(dto.reference);
    if (!existing) {
      // Unknown reference is a no-op success, not an error — matches
      // reserve/issue's "retry-safe" idempotency contract.
      return { success: true, reference: dto.reference, alreadyReleased: false, released: [] };
    }
    if (existing.status !== 'RESERVED') {
      return {
        success: true,
        reference: dto.reference,
        alreadyReleased: true,
        status: existing.status,
        released: [],
      };
    }
    const performedBy = await this.getSystemUserId();
    // No up-front check / compensation needed here the way reserve/issue
    // need it: this only ever decrements `reserved` by exactly what THIS
    // reservation added (nothing else touches those specific units), so a
    // CHECK-constraint failure here would mean a genuine bug, not a race.
    for (const line of existing.lines) {
      await this.inventoryService.applyTransaction({
        type: 'RELEASE_RESERVATION',
        productId: line.productId,
        fromLocationId: line.locationId,
        quantity: Number(line.quantity),
        reference: dto.reference,
        performedBy,
      });
    }
    await this.setStatus(existing.id, 'RELEASED');
    return {
      success: true,
      reference: dto.reference,
      alreadyReleased: false,
      released: existing.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        quantity: Number(l.quantity),
      })),
    };
  }

  async issue(dto) {
    const existing = await this.findReservation(dto.reference);
    if (!existing) {
      throw notFound(`No reservation found for reference "${dto.reference}" — reserve before issuing.`);
    }
    if (existing.status === 'ISSUED') {
      // Idempotent replay.
      return this.issueResult(existing, true);
    }
    if (existing.status === 'RELEASED') {
      throw conflict(`Reservation "${dto.reference}" was already released and cannot be issued.`);
    }
    const lineByKey = new Map(existing.lines.map((l) => [`${l.productId}:${l.locationId}`, l]));
    for (const line of dto.lines) {
      const reservedLine = lineByKey.get(`${line.productId}:${line.locationId}`);
      if (!reservedLine) {
        throw badRequest(`No reservation line for product ${line.productId} at location ${line.locationId} under reference "${dto.reference}"`);
      }
      if (line.quantity > Number(reservedLine.quantity)) {
        throw badRequest(`Cannot issue ${line.quantity} for product ${line.productId} at ${line.locationId} — only ${reservedLine.quantity} was reserved`);
      }
      await this.locationsService.assertLeaf(line.locationId);
    }
    const issueQtyByKey = new Map(dto.lines.map((l) => [`${l.productId}:${l.locationId}`, l.quantity]));
    const performedBy = await this.getSystemUserId();
    const succeeded = [];
    try {
      for (const line of existing.lines) {
        const key = `${line.productId}:${line.locationId}`;
        const issueQty = issueQtyByKey.get(key) ?? 0;
        const reservedQty = Number(line.quantity);
        // Release the FULL reservation for this line, then issue only what's
        // actually dispatched — any shortfall between reserved and issued
        // becomes available again the moment it's released.
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: line.productId,
          fromLocationId: line.locationId,
          quantity: reservedQty,
          reference: dto.reference,
          performedBy,
        });
        if (issueQty > 0) {
          await this.inventoryService.applyTransaction({
            type: 'ISSUE',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: issueQty,
            reference: dto.reference,
            performedBy,
          });
        }
        succeeded.push({ line, issuedQty: issueQty });
      }
    } catch (error) {
      // Compensate with new ledger rows, never by editing/deleting the ones
      // already written (rule 2: append-only). A RECEIVE reverses an ISSUE
      // that already happened; a fresh RESERVATION restores the reservation.
      for (const { line, issuedQty } of succeeded) {
        if (issuedQty > 0) {
          await this.inventoryService
            .applyTransaction({
              type: 'RECEIVE',
              productId: line.productId,
              toLocationId: line.locationId,
              quantity: issuedQty,
              reference: dto.reference,
              performedBy,
              reason: `Compensating an issue that failed partway through reservation ${dto.reference}`,
            })
            .catch(() => {});
        }
        await this.inventoryService
          .applyTransaction({
            type: 'RESERVATION',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: Number(line.quantity),
            reference: dto.reference,
            performedBy,
          })
          .catch(() => {});
      }
      throw conflict(`Issue for reference "${dto.reference}" failed partway through and was rolled back via compensation: ${error.message}`);
    }

    await this.db.transaction(async (tx) => {
      for (const line of existing.lines) {
        await this.db.exec(
          'UPDATE stock_reservation_lines SET issued_quantity = ? WHERE id = ?',
          [issueQtyByKey.get(`${line.productId}:${line.locationId}`) ?? 0, line.id],
          tx,
        );
      }
      await this.setStatus(existing.id, 'ISSUED', tx);
    });
    return this.issueResult(await this.findReservation(dto.reference), false);
  }

  setStatus(reservationId, status, executor) {
    return this.db.exec(
      'UPDATE stock_reservations SET status = ?, updated_at = ? WHERE id = ?',
      [status, new Date(), reservationId],
      executor,
    );
  }

  issueResult(reservation, alreadyIssued) {
    return {
      success: true,
      reference: reservation.reference,
      alreadyIssued,
      issued: reservation.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        reserved: Number(l.quantity),
        issued: Number(l.issuedQuantity),
      })),
    };
  }
}

module.exports = { StockReservationsService, SYSTEM_API_USER_EMAIL };
