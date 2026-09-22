import { Injectable } from '@nestjs/common';
import { WarehouseApiClient } from '../warehouse-api/warehouse-api.client';

/**
 * STEP R3b: a thin, frontend-facing relay over the existing
 * `WarehouseApiClient.getLocations()` — same "no new logic, just expose an
 * internal call" shape as `CatalogueService` (R3a). Named separately from
 * `catalogue` since a location isn't a catalogue concept; it exists purely
 * so a manager reserving an order's stock can pick a real leaf location.
 */
@Injectable()
export class WarehouseLocationsService {
  constructor(private readonly warehouseApi: WarehouseApiClient) {}

  list() {
    return this.warehouseApi.getLocations();
  }
}
