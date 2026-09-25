'use strict';

/**
 * Builds every service once, in dependency order (CLAUDE.md rule 9: cross-module calls go
 * through services, never direct DB reach-ins). A module only receives the services it lists.
 * Each module below is one folder under src/modules with service.js + routes.js.
 */
const { createAuthService } = require('./modules/auth/service');
const { createUsersService } = require('./modules/users/service');
const { createRolesService } = require('./modules/roles/service');
const { createApiKeysService } = require('./modules/api-keys/service');
const { createWarehousesService } = require('./modules/warehouses/service');
const { createLocationsService } = require('./modules/locations/service');
const { createWorkstreamManagersService } = require('./modules/workstream-managers/service');
const { createWorkstreamsService } = require('./modules/workstreams/service');
const { createCategoriesService } = require('./modules/categories/service');
const { createAttributeTypesService } = require('./modules/attribute-types/service');
const { createProductsService } = require('./modules/products/service');
const { createProductImagesService } = require('./modules/product-images/service');
const { InventoryService } = require('./modules/inventory/inventory.service');
const { createReceivingService } = require('./modules/receiving/service');
const { createTransfersService } = require('./modules/transfers/service');
const { StockAdjustmentsService } = require('./modules/stock-adjustments/service');
const { StockCountsService } = require('./modules/stock-counts/service');
const { StockReservationsService } = require('./modules/external-api/stock-reservations.service');
const { createReportsService } = require('./modules/reports/service');
const { ProductImportService } = require('./modules/product-import/product-import.service');
const { ProductImportSessionStore } = require('./modules/product-import/product-import-session.store');

function buildServices({ prisma, cache, config, auth }) {
  const base = { prisma, cache, config };
  const services = {};

  services.auth = createAuthService({ ...base, auth });
  services.users = createUsersService(base);
  services.roles = createRolesService(base);
  services.apiKeys = createApiKeysService(base);
  services.warehouses = createWarehousesService(base);
  services.locations = createLocationsService({ ...base, warehouses: services.warehouses });
  services.workstreamManagers = createWorkstreamManagersService(base);
  services.workstreams = createWorkstreamsService({
    ...base,
    warehouses: services.warehouses,
    workstreamManagers: services.workstreamManagers,
  });
  services.categories = createCategoriesService({
    ...base,
    workstreams: services.workstreams,
    workstreamManagers: services.workstreamManagers,
  });
  services.attributeTypes = createAttributeTypesService(base);
  services.products = createProductsService({
    ...base,
    categories: services.categories,
    attributeTypes: services.attributeTypes,
    workstreamManagers: services.workstreamManagers,
  });
  services.productImages = createProductImagesService({ ...base, products: services.products });
  // In-memory preview->confirm handoff: single-process by design (a lost session just means re-uploading).
  services.productImport = new ProductImportService(
    services.products,
    services.categories,
    services.workstreams,
    services.workstreamManagers,
    services.attributeTypes,
    services.warehouses,
    new ProductImportSessionStore(),
  );


  // ---- Inventory ledger. InventoryService.applyTransaction is the ONLY writer of inventory_balances (rule 2). ----
  services.inventory = new InventoryService(prisma, services.products, services.locations, cache);
  services.receiving = createReceivingService({ inventory: services.inventory, locations: services.locations });
  services.transfers = createTransfersService({ inventory: services.inventory, locations: services.locations });
  services.stockAdjustments = new StockAdjustmentsService(
    prisma,
    services.products,
    services.locations,
    services.inventory,
    cache,
  );
  services.stockCounts = new StockCountsService(prisma, services.products, services.locations, services.stockAdjustments, cache);
  services.stockReservations = new StockReservationsService(prisma, services.products, services.locations, services.inventory);

  services.reports = createReportsService({
    ...base,
    products: services.products,
    categories: services.categories,
    workstreams: services.workstreams,
    warehouses: services.warehouses,
    inventory: services.inventory,
    stockAdjustments: services.stockAdjustments,
    stockCounts: services.stockCounts,
  });

  return services;
}

module.exports = { buildServices };
