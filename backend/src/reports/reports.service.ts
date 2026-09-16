import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { OrdersReportQueryDto } from './dto/orders-report-query.dto';

const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Read-only reporting layer (Phase 1G), order-side only. Step 4 of the
 * system split (ARCHITECTURE.md §A2) removed the inventory/catalogue
 * reports (low-stock, stock-movement, inventory-valuation, receiving,
 * transfers, adjustments) — those tables live in warehouse_db now and the
 * equivalent reports already exist in /warehouse. Only the order-side
 * report stays here.
 */
@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

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
}
