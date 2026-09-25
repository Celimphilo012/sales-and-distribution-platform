'use strict';

const { TAGS } = require('../../core/cache/cache');

/**
 * Reports + the dashboard's one aggregated payload. Every number is a DB-level aggregate (groupBy /
 * count / raw SQL) — never a full-table fetch summed in JS.
 *
 * These are the most expensive reads in the API and the dashboard is the first screen everyone
 * opens, so they are cached. Correctness comes from tags, not from a short TTL alone: anything that
 * can change a number invalidates it —
 *   STOCK      every ledger write (applyTransaction), adjustments, counts
 *   CATALOGUE  products (min level, cost price, status), categories, workstreams, attribute types
 *   STRUCTURE  warehouses / locations (active-location filter, warehouse count)
 * The TTL then only bounds staleness for time-relative figures ("last 7 days", "waiting N days")
 * and for changes made by another process.
 */
function createReportsService({
  cache,
  config,
  products,
  categories,
  workstreams,
  warehouses,
  inventory,
  stockAdjustments,
  stockCounts,
}) {
  const opts = { ttlMs: config.cache.reportsTtlMs, tags: [TAGS.STOCK, TAGS.CATALOGUE, TAGS.STRUCTURE] };

  const getLowStock = () =>
    cache.wrap('reports:low-stock', opts, async () => {
      const items = await inventory.getLowStockProducts();
      return { count: items.length, items };
    });

  const getInventoryValuation = () => cache.wrap('reports:valuation', opts, () => inventory.getInventoryValuation());

  const getStockMovementSummary = (days) =>
    cache.wrap(`reports:movement:${days ?? 'default'}`, opts, () => inventory.getStockMovementSummary(days));

  const getAdjustmentsSummary = (days) =>
    cache.wrap(`reports:adjustments:${days ?? 'default'}`, opts, () => stockAdjustments.getAdjustmentsSummary(days));

  /**
   * The dashboard's one aggregated payload. Every field is a slice of a query the methods above
   * already run — nothing here is a duplicate query, and the whole batch runs in parallel.
   */
  const getDashboard = () =>
    cache.wrap('reports:dashboard', opts, async () => {
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
        products.countActive(),
        categories.countActive(),
        workstreams.countActive(),
        warehouses.countActive(),
        inventory.getLowStockProducts(),
        stockAdjustments.getAdjustmentsSummary(7),
        inventory.getInventoryValuation(),
        inventory.getStockMovementSummary(7),
        stockCounts.countOpen(),
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
