import { Injectable } from '@nestjs/common';
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
 * One summary payload for manager dashboard cards — order side only. Step 4
 * of the system split (ARCHITECTURE.md §A2) removed the inventory half
 * (lowStockCount, pendingAdjustmentsCount) — those tables live in
 * warehouse_db now. Step 5/6 may re-stitch an inventory summary back in via
 * the warehouse API.
 */
@Injectable()
export class DashboardService {
  constructor(private readonly reportsService: ReportsService) {}

  async getSummary() {
    const [ordersOverall, todayOrders, thisWeekOrders] = await Promise.all([
      this.reportsService.getOrdersReport(),
      this.reportsService.getOrdersReport({ from: startOfToday().toISOString() }),
      this.reportsService.getOrdersReport({ from: startOfThisWeek().toISOString() }),
    ]);

    return {
      ordersByStatus: ordersOverall.byStatus,
      today: { orderCount: todayOrders.count, totalValue: todayOrders.totalValue },
      thisWeek: { orderCount: thisWeekOrders.count, totalValue: thisWeekOrders.totalValue },
    };
  }
}
