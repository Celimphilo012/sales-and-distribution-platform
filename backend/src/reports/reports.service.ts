import { Injectable } from '@nestjs/common';
import { InventoryTransactionType, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { StockMovementQueryDto } from './dto/stock-movement-query.dto';
import { LedgerReportQueryDto } from './dto/ledger-report-query.dto';
import { OrdersReportQueryDto } from './dto/orders-report-query.dto';

const round2 = (n: number) => Math.round(n * 100) / 100;

const TRANSACTION_INCLUDE = {
  product: { select: { id: true, sku: true, name: true, uom: true } },
  fromLocation: { select: { id: true, name: true, code: true } },
  toLocation: { select: { id: true, name: true, code: true } },
  performedByUser: { select: { id: true, fullName: true } },
} as const;

/**
 * Read-only reporting layer (Phase 1G). Every method reads directly from
 * the tables the rest of the system already writes —
 * inventory_balances/inventory_transactions via InventoryService's own
 * writes, orders/order_items via OrdersService's — and never recomputes a
 * quantity a second, parallel way. No table here is new; nothing here
 * writes anything.
 */
@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Products whose on_hand, summed across every location, is below their
   * min_stock_level. Reads inventory_balances directly (the same cache
   * table InventoryService.applyTransaction() maintains) — never the
   * ledger recomputed independently.
   */
  async getLowStock() {
    const [products, balanceSums] = await Promise.all([
      this.prisma.product.findMany({
        where: { status: 'ACTIVE' },
        select: { id: true, sku: true, name: true, uom: true, minStockLevel: true },
      }),
      this.prisma.inventoryBalance.groupBy({ by: ['productId'], _sum: { onHand: true } }),
    ]);

    const onHandByProduct = new Map(balanceSums.map((b) => [b.productId, Number(b._sum.onHand ?? 0)]));

    const rows = products
      .map((product) => {
        const totalOnHand = onHandByProduct.get(product.id) ?? 0;
        const minStockLevel = Number(product.minStockLevel);
        return {
          productId: product.id,
          sku: product.sku,
          name: product.name,
          uom: product.uom,
          totalOnHand,
          minStockLevel,
          shortfall: round2(minStockLevel - totalOnHand),
        };
      })
      .filter((row) => row.totalOnHand < row.minStockLevel)
      .sort((a, b) => b.shortfall - a.shortfall);

    return { count: rows.length, products: rows };
  }

  /** A filtered read of inventory_transactions, with a type-grouped summary. Nothing else. */
  async getStockMovement(query: StockMovementQueryDto) {
    const where = this.buildTransactionWhere(query.productId, query.locationId, query.from, query.to, query.type);

    const [summary, transactions] = await Promise.all([
      this.prisma.inventoryTransaction.groupBy({
        by: ['type'],
        where,
        _count: { _all: true },
        _sum: { quantity: true },
      }),
      this.prisma.inventoryTransaction.findMany({
        where,
        include: TRANSACTION_INCLUDE,
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    return {
      filters: query,
      summary: summary.map((s) => ({
        type: s.type,
        count: s._count._all,
        totalQuantity: Number(s._sum.quantity ?? 0),
      })),
      transactions,
    };
  }

  /**
   * sum(on_hand * cost_price) per product and overall. cost_price is
   * nullable (Phase 1B) — a product with no cost_price is EXCLUDED from
   * the total and reported separately, never treated as cost_price = 0
   * (that would silently understate the total instead of flagging the
   * gap).
   */
  async getInventoryValuation() {
    const [products, balanceSums] = await Promise.all([
      this.prisma.product.findMany({
        select: { id: true, sku: true, name: true, uom: true, costPrice: true },
      }),
      this.prisma.inventoryBalance.groupBy({ by: ['productId'], _sum: { onHand: true } }),
    ]);

    const onHandByProduct = new Map(balanceSums.map((b) => [b.productId, Number(b._sum.onHand ?? 0)]));

    const valued: { productId: string; sku: string; name: string; totalOnHand: number; costPrice: number; valuation: number }[] = [];
    const excluded: { productId: string; sku: string; name: string; totalOnHand: number }[] = [];

    for (const product of products) {
      const totalOnHand = onHandByProduct.get(product.id) ?? 0;
      if (totalOnHand <= 0) continue; // zero stock contributes nothing either way — not a meaningful inclusion or exclusion

      if (product.costPrice === null) {
        excluded.push({ productId: product.id, sku: product.sku, name: product.name, totalOnHand });
        continue;
      }

      const costPrice = Number(product.costPrice);
      valued.push({
        productId: product.id,
        sku: product.sku,
        name: product.name,
        totalOnHand,
        costPrice,
        valuation: round2(totalOnHand * costPrice),
      });
    }

    const totalValuation = round2(valued.reduce((sum, p) => sum + p.valuation, 0));

    return {
      totalValuation,
      costedProductCount: valued.length,
      products: valued,
      excludedCount: excluded.length,
      excludedProducts: excluded,
    };
  }

  /**
   * Filtered orders + totals. count/totalValue/byStatus all derive from
   * orders.status and orders.total — never recomputed from order_items'
   * unit_price * quantity. Called with no filters, this is also the
   * dashboard's order-pipeline-by-status source.
   */
  async getOrdersReport(query: OrdersReportQueryDto = {}) {
    const where: Prisma.OrderWhereInput = {
      status: query.status,
      customerId: query.customerId,
      orderDate: {
        gte: query.from ? new Date(query.from) : undefined,
        lte: query.to ? new Date(query.to) : undefined,
      },
    };

    const [orders, byStatus] = await Promise.all([
      this.prisma.order.findMany({
        where,
        select: {
          id: true,
          orderNumber: true,
          status: true,
          paymentStatus: true,
          customerId: true,
          consultantId: true,
          orderDate: true,
          total: true,
          customer: { select: { id: true, name: true } },
        },
        orderBy: { orderDate: 'desc' },
      }),
      this.prisma.order.groupBy({
        by: ['status'],
        where,
        _count: { _all: true },
        _sum: { total: true },
      }),
    ]);

    const count = orders.length;
    const totalValue = round2(orders.reduce((sum, o) => sum + Number(o.total), 0));

    return {
      filters: query,
      count,
      totalValue,
      byStatus: byStatus.map((s) => ({
        status: s.status,
        count: s._count._all,
        totalValue: round2(Number(s._sum.total ?? 0)),
      })),
      orders,
    };
  }

  /** RECEIVE-type ledger rows, filtered. */
  async getReceivingReport(query: LedgerReportQueryDto) {
    const where = this.buildTransactionWhere(query.productId, query.locationId, query.from, query.to, 'RECEIVE');
    const transactions = await this.prisma.inventoryTransaction.findMany({
      where,
      include: TRANSACTION_INCLUDE,
      orderBy: { createdAt: 'desc' },
    });
    return { filters: query, count: transactions.length, transactions };
  }

  /** TRANSFER-type ledger rows, filtered. */
  async getTransfersReport(query: LedgerReportQueryDto) {
    const where = this.buildTransactionWhere(query.productId, query.locationId, query.from, query.to, 'TRANSFER');
    const transactions = await this.prisma.inventoryTransaction.findMany({
      where,
      include: TRANSACTION_INCLUDE,
      orderBy: { createdAt: 'desc' },
    });
    return { filters: query, count: transactions.length, transactions };
  }

  /**
   * ADJUSTMENT-type ledger rows, filtered, each enriched with its
   * originating stock_adjustments row (requester/approver/status) where
   * one can be identified.
   *
   * IMPORTANT LIMITATION: inventory_transactions has no FK back to
   * stock_adjustments — Phase 1D's StockAdjustmentsService.approve()
   * calls the frozen applyTransaction() and then separately updates the
   * stock_adjustments row, but never persists the resulting transaction
   * id anywhere (and this phase cannot modify that frozen code to add
   * one). So the match below is a best-effort correlation — product,
   * location, quantity, reviewer = performedBy, status APPROVED — not a
   * guaranteed relational join. In the overwhelming common case (one
   * reviewer approving one request for a given product/location/qty) this
   * is exact; a genuine ambiguity (the same reviewer approving two
   * identical-quantity requests for the same product/location) falls back
   * to the most recently reviewed match.
   */
  async getAdjustmentsReport(query: LedgerReportQueryDto) {
    const where = this.buildTransactionWhere(query.productId, query.locationId, query.from, query.to, 'ADJUSTMENT');
    const transactions = await this.prisma.inventoryTransaction.findMany({
      where,
      include: TRANSACTION_INCLUDE,
      orderBy: { createdAt: 'desc' },
    });

    const enriched = await Promise.all(
      transactions.map(async (tx) => {
        const locationId = tx.toLocationId ?? tx.fromLocationId ?? undefined;
        const adjustment = locationId
          ? await this.prisma.stockAdjustment.findFirst({
              where: {
                productId: tx.productId,
                locationId,
                delta: tx.quantity,
                reviewedBy: tx.performedBy,
                status: 'APPROVED',
              },
              orderBy: { reviewedAt: 'desc' },
              select: {
                id: true,
                bucket: true,
                direction: true,
                reason: true,
                status: true,
                requestedAt: true,
                reviewedAt: true,
                reviewNote: true,
                requestedByUser: { select: { id: true, fullName: true } },
                reviewedByUser: { select: { id: true, fullName: true } },
              },
            })
          : null;
        return { ...tx, adjustment };
      }),
    );

    return { filters: query, count: enriched.length, transactions: enriched };
  }

  private buildTransactionWhere(
    productId?: string,
    locationId?: string,
    from?: string,
    to?: string,
    type?: InventoryTransactionType,
  ): Prisma.InventoryTransactionWhereInput {
    return {
      productId,
      type,
      OR: locationId ? [{ fromLocationId: locationId }, { toLocationId: locationId }] : undefined,
      createdAt: {
        gte: from ? new Date(from) : undefined,
        lte: to ? new Date(to) : undefined,
      },
    };
  }
}
