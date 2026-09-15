import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { ReportsService } from '../reports/reports.service';

function startOfToday(): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

/** Monday 00:00 of the current ISO week. */
function startOfThisWeek(): Date {
  const d = startOfToday();
  const day = d.getDay(); // 0 = Sunday
  const diffToMonday = day === 0 ? 6 : day - 1;
  d.setDate(d.getDate() - diffToMonday);
  return d;
}

/**
 * One summary payload for manager dashboard cards. Pure aggregation of
 * the Phase 1G reports (reuses ReportsService — no parallel query logic)
 * plus a single direct count for pending adjustments. No writes, no new
 * tables.
 */
@Injectable()
export class DashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly reportsService: ReportsService,
  ) {}

  async getSummary() {
    const [ordersOverall, lowStock, pendingAdjustmentsCount, todayOrders, thisWeekOrders] = await Promise.all([
      this.reportsService.getOrdersReport(),
      this.reportsService.getLowStock(),
      this.prisma.stockAdjustment.count({ where: { status: 'PENDING' } }),
      this.reportsService.getOrdersReport({ from: startOfToday().toISOString() }),
      this.reportsService.getOrdersReport({ from: startOfThisWeek().toISOString() }),
    ]);

    return {
      ordersByStatus: ordersOverall.byStatus,
      lowStockCount: lowStock.count,
      pendingAdjustmentsCount,
      today: { orderCount: todayOrders.count, totalValue: todayOrders.totalValue },
      thisWeek: { orderCount: thisWeekOrders.count, totalValue: thisWeekOrders.totalValue },
    };
  }
}
