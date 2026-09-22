import { Injectable } from '@nestjs/common';
import { ProductsService } from '../products/products.service';
import { CategoriesService } from '../categories/categories.service';
import { WorkstreamsService } from '../workstreams/workstreams.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { InventoryService } from '../inventory/inventory.service';
import { StockAdjustmentsService } from '../stock-adjustments/stock-adjustments.service';
import { StockCountsService } from '../stock-counts/stock-counts.service';

/**
 * Pure orchestrator — every number here comes from an owning service's own
 * aggregate query (rule 9: no direct Prisma reach-ins for tables this module
 * doesn't own). Nothing in this service touches PrismaService directly, and
 * nothing writes anything; every method here backs a `reports.view`-gated
 * GET.
 */
@Injectable()
export class ReportsService {
  constructor(
    private readonly productsService: ProductsService,
    private readonly categoriesService: CategoriesService,
    private readonly workstreamsService: WorkstreamsService,
    private readonly warehousesService: WarehousesService,
    private readonly inventoryService: InventoryService,
    private readonly stockAdjustmentsService: StockAdjustmentsService,
    private readonly stockCountsService: StockCountsService,
  ) {}

  async getLowStock() {
    const items = await this.inventoryService.getLowStockProducts();
    return { count: items.length, items };
  }

  getInventoryValuation() {
    return this.inventoryService.getInventoryValuation();
  }

  getStockMovementSummary(days?: number) {
    return this.inventoryService.getStockMovementSummary(days);
  }

  getAdjustmentsSummary(days?: number) {
    return this.stockAdjustmentsService.getAdjustmentsSummary(days);
  }

  /**
   * The dashboard's one aggregated payload. Every field is a slice of a
   * query the methods above already run — nothing here is a duplicate
   * query, and the whole batch runs in parallel since each is already a
   * cheap DB-level aggregate.
   */
  async getDashboard() {
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
      this.productsService.countActive(),
      this.categoriesService.countActive(),
      this.workstreamsService.countActive(),
      this.warehousesService.countActive(),
      this.inventoryService.getLowStockProducts(),
      this.stockAdjustmentsService.getAdjustmentsSummary(7),
      this.inventoryService.getInventoryValuation(),
      this.inventoryService.getStockMovementSummary(7),
      this.stockCountsService.countOpen(),
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
  }
}
