import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ReportsService } from './reports.service';
import { StockMovementQueryDto } from './dto/stock-movement-query.dto';
import { LedgerReportQueryDto } from './dto/ledger-report-query.dto';
import { OrdersReportQueryDto } from './dto/orders-report-query.dto';

// Phase 1G: read-only. Every route here is a GET that aggregates existing
// tables — no writes, no new tables, no AuditInterceptor activity (it only
// fires on POST/PUT/PATCH/DELETE, none of which exist in this module).
@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('reports.view')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('low-stock')
  getLowStock() {
    return this.reportsService.getLowStock();
  }

  @Get('stock-movement')
  getStockMovement(@Query() query: StockMovementQueryDto) {
    return this.reportsService.getStockMovement(query);
  }

  @Get('inventory-valuation')
  getInventoryValuation() {
    return this.reportsService.getInventoryValuation();
  }

  @Get('orders')
  getOrdersReport(@Query() query: OrdersReportQueryDto) {
    return this.reportsService.getOrdersReport(query);
  }

  @Get('receiving')
  getReceivingReport(@Query() query: LedgerReportQueryDto) {
    return this.reportsService.getReceivingReport(query);
  }

  @Get('transfers')
  getTransfersReport(@Query() query: LedgerReportQueryDto) {
    return this.reportsService.getTransfersReport(query);
  }

  @Get('adjustments')
  getAdjustmentsReport(@Query() query: LedgerReportQueryDto) {
    return this.reportsService.getAdjustmentsReport(query);
  }
}
