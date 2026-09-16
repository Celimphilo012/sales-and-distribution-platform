import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ReportsService } from './reports.service';
import { OrdersReportQueryDto } from './dto/orders-report-query.dto';

// Phase 1G: read-only. Step 4 of the system split (ARCHITECTURE.md §A2)
// removed every inventory/catalogue report route (low-stock, stock-movement,
// inventory-valuation, receiving, transfers, adjustments) — those now live
// in /warehouse. Only the order report stays here.
@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('reports.view')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('orders')
  getOrdersReport(@Query() query: OrdersReportQueryDto) {
    return this.reportsService.getOrdersReport(query);
  }
}
