'use strict';

const { TAGS } = require('../../core/cache/cache');

/**
 * Reports + the dashboard's one aggregated payload. Every number is a DB-level aggregate (GROUP BY /
 * COUNT / SUM in SQL) — never a full-table fetch summed in JS — and every number is limited to the
 * viewer's warehouses (modules/access): a user assigned to one warehouse sees that warehouse's
 * figures only.
 *
 * These are the most expensive reads in the API and the dashboard is the first screen everyone
 * opens, so they are cached — per warehouse scope. Correctness comes from tags, not from a short
 * TTL alone: anything that can change a number invalidates it —
 *   STOCK      every ledger write (applyTransaction), adjustments, counts
 *   CATALOGUE  products (min level, cost price, status), categories, workstreams, attribute types
 *   STRUCTURE  warehouses / locations (active-location filter, warehouse count)
 * The TTL then only bounds staleness for time-relative figures ("last 7 days", "waiting N days")
 * and for changes made by another process.
 */
function createReportsService({
  cache,
  config,
  access,
  products,
  categories,
  workstreams,
  warehouses,
  inventory,
  stockAdjustments,
  stockCounts,
}) {
  const opts = { ttlMs: config.cache.reportsTtlMs, tags: [TAGS.STOCK, TAGS.CATALOGUE, TAGS.STRUCTURE, TAGS.SCOPES] };

  /** Runs `load(scope)` cached under `name` + the viewer's warehouse scope. */
  async function scoped(name, viewerId, load) {
    const scope = await access.warehouseScope(viewerId);
    return cache.wrap(`reports:${name}:${access.scopeKey(scope)}`, opts, () => load(scope));
  }

  const getLowStock = (viewerId) =>
    scoped('low-stock', viewerId, async (scope) => {
      const items = await inventory.getLowStockProducts(scope);
      return { count: items.length, items };
    });

  const getInventoryValuation = (viewerId) =>
    scoped('valuation', viewerId, (scope) => inventory.getInventoryValuation(scope));

  const getStockMovementSummary = (days, viewerId) =>
    scoped(`movement:${days ?? 'default'}`, viewerId, (scope) => inventory.getStockMovementSummary(days, scope));

  const getAdjustmentsSummary = (days, viewerId) =>
    scoped(`adjustments:${days ?? 'default'}`, viewerId, (scope) => stockAdjustments.getAdjustmentsSummary(days, scope));

  /**
   * The dashboard's one aggregated payload. Every field is a slice of a query the methods above
   * already run — nothing here is a duplicate query, and the whole batch runs in parallel.
   */
  const getDashboard = (viewerId) =>
    scoped('dashboard', viewerId, async (scope) => {
      const [
        activeProductCount,
        activeCategoryCount,
        activeWorkstreamCount,
        activeWarehouseCount,
        lowStockItems,
        adjustmentsSummary,
        valuation,
        stockMovement,
        openStockCountsCount,
      ] = await Promise.all([
        products.countActive(scope),
        categories.countActive(scope),
        workstreams.countActive(scope),
        warehouses.countActive(scope),
        inventory.getLowStockProducts(scope),
        stockAdjustments.getAdjustmentsSummary(7, scope),
        inventory.getInventoryValuation(scope),
        inventory.getStockMovementSummary(7, scope),
        stockCounts.countOpen(scope),
      ]);

      return {
        catalogue: { activeProductCount, activeCategoryCount, activeWorkstreamCount, activeWarehouseCount },
        lowStock: { count: lowStockItems.length, topItems: lowStockItems.slice(0, 5) },
        pendingAdjustments: {
          count: adjustmentsSummary.totalPendingCount,
          oldestItems: adjustmentsSummary.oldestPending.slice(0, 5),
        },
        valuation,
        stockMovement,
        openStockCounts: { count: openStockCountsCount },
      };
    });

  return { getLowStock, getInventoryValuation, getStockMovementSummary, getAdjustmentsSummary, getDashboard };
}

module.exports = { createReportsService };
