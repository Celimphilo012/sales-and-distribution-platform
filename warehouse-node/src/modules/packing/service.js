'use strict';

/**
 * "What do I need to pack?" — the open orders' items, for the warehouse and workstream people who
 * help package them.
 *
 * Orders live in the ordering system's own database (never read from here — ARCHITECTURE §A2). What
 * the warehouse DOES know is every reservation the ordering system made through the external API:
 * `stock_reservations` (reference = the order id, label = e.g. "ORD-0012 · Customer") and its lines
 * (product, location, quantity). A reservation that is still RESERVED is an order that has been
 * allocated stock but not yet dispatched — exactly the ones waiting to be picked and packed.
 *
 * Each user sees only the lines they can act on:
 *   - lines whose pick location is in one of their warehouses (modules/access), and
 *   - if they are assigned to manage specific workstreams, only products from those workstreams.
 * An order appears if at least one of its lines is visible; `totalLineCount` tells them how many
 * lines the whole order has, so they know other people are packing the rest.
 */
function createPackingService({ db, access, workstreamManagers }) {
  async function openOrders(viewerId, { workstreamId } = {}) {
    const [warehouseIds, managedIds] = await Promise.all([
      access.warehouseScope(viewerId),
      workstreamManagers.getAssignedWorkstreamIds(viewerId),
    ]);
    if (warehouseIds !== null && warehouseIds.length === 0) return [];

    const filters = ["r.status = 'RESERVED'"];
    const params = [];
    if (warehouseIds !== null) {
      filters.push('loc.warehouse_id IN (?)');
      params.push(warehouseIds);
    }
    if (managedIds.length > 0) {
      filters.push('w.id IN (?)');
      params.push(managedIds);
    }
    if (workstreamId) {
      filters.push('w.id = ?');
      params.push(workstreamId);
    }

    const rows = await db.query(
      `SELECT r.id AS reservationId, r.reference, r.label, r.created_at AS reservedAt,
              (SELECT COUNT(*) FROM stock_reservation_lines al WHERE al.reservation_id = r.id) AS totalLineCount,
              l.id AS lineId, l.quantity,
              p.id AS productId, p.sku, p.name AS productName, p.uom,
              w.id AS workstreamId, w.name AS workstreamName, w.code AS workstreamCode,
              loc.id AS locationId, loc.name AS locationName, loc.code AS locationCode,
              wh.id AS warehouseId, wh.name AS warehouseName, wh.code AS warehouseCode
         FROM stock_reservations r
         JOIN stock_reservation_lines l ON l.reservation_id = r.id
         JOIN products p ON p.id = l.product_id
         JOIN categories c ON c.id = p.category_id
         JOIN workstreams w ON w.id = c.workstream_id
         JOIN locations loc ON loc.id = l.location_id
         JOIN warehouses wh ON wh.id = loc.warehouse_id
        WHERE ${filters.join(' AND ')}
        ORDER BY r.created_at ASC, w.name ASC, p.name ASC`,
      params,
    );

    // Oldest order first (pack in the order things were reserved); lines grouped under their order.
    const orders = new Map();
    for (const row of rows) {
      if (!orders.has(row.reservationId)) {
        orders.set(row.reservationId, {
          reference: row.reference,
          label: row.label,
          reservedAt: row.reservedAt,
          totalLineCount: Number(row.totalLineCount),
          lines: [],
        });
      }
      orders.get(row.reservationId).lines.push({
        id: row.lineId,
        quantity: Number(row.quantity),
        product: { id: row.productId, sku: row.sku, name: row.productName, uom: row.uom },
        workstream: { id: row.workstreamId, name: row.workstreamName, code: row.workstreamCode },
        location: { id: row.locationId, name: row.locationName, code: row.locationCode },
        warehouse: { id: row.warehouseId, name: row.warehouseName, code: row.warehouseCode },
      });
    }
    return [...orders.values()];
  }

  return { openOrders };
}

module.exports = { createPackingService };
