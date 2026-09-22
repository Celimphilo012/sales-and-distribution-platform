import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ReportsService } from './reports.service';

/**
 * Separate controller (same module, same service) so the route is the bare
 * `/dashboard` the frontend's homepage expects, rather than nested under
 * `/reports`.
 */
@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('dashboard')
export class DashboardController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get()
  @RequirePermissions('reports.view')
  getDashboard() {
    return this.reportsService.getDashboard();
  }
}
