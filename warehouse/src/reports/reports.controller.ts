import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ReportsService } from './reports.service';
import { PeriodQueryDto } from './dto/period-query.dto';

@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('reports')
@RequirePermissions('reports.view')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('low-stock')
  getLowStock() {
    return this.reportsService.getLowStock();
  }

  @Get('inventory-valuation')
  getInventoryValuation() {
    return this.reportsService.getInventoryValuation();
  }

  @Get('stock-movement-summary')
  getStockMovementSummary(@Query() query: PeriodQueryDto) {
    return this.reportsService.getStockMovementSummary(query.days);
  }

  @Get('adjustments-summary')
  getAdjustmentsSummary(@Query() query: PeriodQueryDto) {
    return this.reportsService.getAdjustmentsSummary(query.days);
  }
}
