'use strict';

/**
 * Where an order's stock should be reserved from — the automatic proposal behind "Reserve stock".
 *
 * Rules (the user's decisions, 2026-09-29):
 *  - ONE warehouse per order: every line comes from the same warehouse, so an order ships from one place.
 *  - Oldest stock first (FIFO): within that warehouse, each line takes from the locations whose stock
 *    arrived earliest (the warehouse's `oldestStockAt`), then the fuller location, then a stable order.
 *  - A line may be SPLIT across several locations when no single one holds enough.
 *  - Lines of the same product share the same pool: stock planned for one line is not offered again.
 * Choosing the warehouse: among warehouses that can fill the whole order, the one whose planned stock
 * is oldest (then the one needing fewer pick locations). If none can, the proposal is the warehouse
 * that covers the most, marked incomplete with each line's shortfall — reserving is then refused.
 *
 * This only PLANS. The warehouse re-checks availability atomically when the reservation is made, so a
 * plan that went stale (someone reserved in between) fails cleanly with the short lines.
 */

const round3 = (n) => Math.round(n * 1000) / 1000;
const EPSILON = 0.0005;

const byFifo = (a, b) => {
  const ta = a.oldestStockAt ? new Date(a.oldestStockAt).getTime() : Infinity;
  const tb = b.oldestStockAt ? new Date(b.oldestStockAt).getTime() : Infinity;
  if (ta !== tb) return ta - tb;
  if (a.available !== b.available) return b.available - a.available;
  return a.locationId < b.locationId ? -1 : 1;
};

/**
 * items:   [{ id, productId, quantity }]
 * options: [{ productId, locations: [{ locationId, warehouseId, available, oldestStockAt }] }]
 * Returns { warehouseId, complete, lines: [{ orderItemId, allocations: [{ locationId, quantity }], shortBy }],
 *           alternatives: [{ warehouseId, complete, covered }] }.
 */
function planAllocation(items, options, { warehouseId: forcedWarehouseId } = {}) {
  const byProduct = new Map(options.map((o) => [o.productId, o.locations]));
  const warehouseIds = [...new Set(options.flatMap((o) => o.locations.map((l) => l.warehouseId)))];

  function planFor(warehouseId) {
    const remaining = new Map(); // productId:locationId -> still available in this plan
    let oldest = Infinity;
    let pickCount = 0;
    const lines = items.map((item) => {
      let need = round3(Number(item.quantity));
      const allocations = [];
      const candidates = (byProduct.get(item.productId) ?? []).filter((l) => l.warehouseId === warehouseId).sort(byFifo);
      for (const loc of candidates) {
        if (need <= EPSILON) break;
        const key = `${item.productId}:${loc.locationId}`;
        const left = remaining.has(key) ? remaining.get(key) : loc.available;
        const take = round3(Math.min(need, left));
        if (take <= EPSILON) continue;
        remaining.set(key, round3(left - take));
        allocations.push({ locationId: loc.locationId, quantity: take });
        need = round3(need - take);
        pickCount += 1;
        if (loc.oldestStockAt) oldest = Math.min(oldest, new Date(loc.oldestStockAt).getTime());
      }
      return { orderItemId: item.id, allocations, shortBy: need > EPSILON ? need : 0 };
    });
    const complete = lines.every((l) => l.shortBy === 0);
    const covered = round3(items.reduce((sum, item, i) => sum + Number(item.quantity) - lines[i].shortBy, 0));
    return { warehouseId, complete, covered, oldest, pickCount, lines };
  }

  const plans = warehouseIds.map(planFor);
  let chosen;
  if (forcedWarehouseId) {
    chosen = plans.find((p) => p.warehouseId === forcedWarehouseId) ?? planFor(forcedWarehouseId);
  } else {
    const complete = plans.filter((p) => p.complete).sort((a, b) => a.oldest - b.oldest || a.pickCount - b.pickCount);
    chosen = complete[0] ?? [...plans].sort((a, b) => b.covered - a.covered)[0];
  }
  if (!chosen) {
    // Nothing anywhere: every line is short by its whole quantity.
    return {
      warehouseId: null,
      complete: false,
      lines: items.map((item) => ({ orderItemId: item.id, allocations: [], shortBy: round3(Number(item.quantity)) })),
      alternatives: [],
    };
  }
  return {
    warehouseId: chosen.warehouseId,
    complete: chosen.complete,
    lines: chosen.lines,
    alternatives: plans.map((p) => ({ warehouseId: p.warehouseId, complete: p.complete, covered: p.covered })),
  };
}

module.exports = { planAllocation, byFifo };
