import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { ApiKeyGuard } from '../common/guards/api-key.guard';
import { RequireScopes } from '../common/decorators/require-scopes.decorator';
import { LocationsService } from '../locations/locations.service';
import { WarehousesService } from '../warehouses/warehouses.service';

/**
 * STEP R3b: system-to-system location read — authenticated by API key
 * (`ApiKeyGuard`), never a user JWT, same as the rest of `/api/v1/*`. Lets
 * the back-office relay a real leaf-location picker for order reservation
 * (`ReserveOrderDto.allocations[].locationId` needs a real location id; the
 * back-office had no way to discover one before this). Active locations
 * only, flat (no ancestor chain) — same shape/limitation the internal
 * `/locations` route already has (ARCHITECTURE.md's 6d note); a consumer
 * resolves the path client-side by walking `parentId`, same as
 * `/warehouse-frontend` already does. Reuses `LocationsService`/
 * `WarehousesService` as-is — no new business logic, purely a read view for
 * an external consumer.
 */
@ApiTags('external-locations')
@UseGuards(ApiKeyGuard)
@RequireScopes('locations:read')
@Controller('api/v1/locations')
export class ExternalLocationsController {
  constructor(
    private readonly locationsService: LocationsService,
    private readonly warehousesService: WarehousesService,
  ) {}

  @Get()
  async getLocations() {
    const [warehouses, locations] = await Promise.all([
      this.warehousesService.findAll(),
      this.locationsService.findAll(),
    ]);
    return { warehouses, locations };
  }
}
