import { Injectable } from '@nestjs/common';
import { WarehouseApiClient } from '../warehouse-api/warehouse-api.client';
import { ListCatalogueQueryDto } from './dto/list-catalogue-query.dto';

/**
 * STEP R3a: a thin, frontend-facing relay over the existing internal
 * `WarehouseApiClient` (step 5) — no new warehouse call, no new logic. Step
 * 5 only used `WarehouseApiClient.getCatalogue()`/`getProduct()` internally
 * (price/name snapshotting on order-line creation, JWT never reaches the
 * warehouse); there was no route the ordering FRONTEND could call to browse
 * products for a picker. This exposes exactly that, still going through the
 * same API-key client — the frontend never talks to the warehouse directly
 * (ARCHITECTURE.md §A2).
 */
@Injectable()
export class CatalogueService {
  constructor(private readonly warehouseApi: WarehouseApiClient) {}

  // Always ACTIVE-only: a picker for building an order should never offer a
  // product `buildLineInputs()` would reject at save time anyway.
  list(query: ListCatalogueQueryDto) {
    return this.warehouseApi.getCatalogue({ search: query.search, status: 'ACTIVE' });
  }
}
