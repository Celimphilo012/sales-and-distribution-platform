import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { CategoriesModule } from '../categories/categories.module';
import { LocationsModule } from '../locations/locations.module';
import { WarehousesModule } from '../warehouses/warehouses.module';
import { InventoryModule } from '../inventory/inventory.module';
import { ExternalCatalogueController } from './external-catalogue.controller';
import { ExternalStockController } from './external-stock.controller';
import { ExternalLocationsController } from './external-locations.controller';
import { StockReservationsService } from './stock-reservations.service';

@Module({
  imports: [ProductsModule, CategoriesModule, LocationsModule, WarehousesModule, InventoryModule],
  controllers: [ExternalCatalogueController, ExternalStockController, ExternalLocationsController],
  providers: [StockReservationsService],
})
export class ExternalApiModule {}
