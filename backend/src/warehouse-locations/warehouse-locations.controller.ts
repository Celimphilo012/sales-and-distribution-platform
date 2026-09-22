import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { WarehouseLocationsService } from './warehouse-locations.service';

/**
 * STEP R3b: the ordering FRONTEND-facing location read, JWT-guarded (NOT
 * the warehouse's API-key boundary — that stays system-to-system,
 * ARCHITECTURE.md §A2), gated `orders.approve` — the only permission that
 * ever needs this (reserving an order's stock, `POST /orders/:id/reserve`,
 * is gated the same way).
 */
@ApiTags('warehouse-locations')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('orders.approve')
@Controller('warehouse-locations')
export class WarehouseLocationsController {
  constructor(private readonly warehouseLocationsService: WarehouseLocationsService) {}

  @Get()
  list() {
    return this.warehouseLocationsService.list();
  }
}
