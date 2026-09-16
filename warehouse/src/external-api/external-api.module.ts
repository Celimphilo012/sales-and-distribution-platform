import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { CategoriesModule } from '../categories/categories.module';
import { LocationsModule } from '../locations/locations.module';
import { InventoryModule } from '../inventory/inventory.module';
import { ExternalCatalogueController } from './external-catalogue.controller';
import { ExternalStockController } from './external-stock.controller';
import { StockReservationsService } from './stock-reservations.service';

@Module({
  imports: [ProductsModule, CategoriesModule, LocationsModule, InventoryModule],
  controllers: [ExternalCatalogueController, ExternalStockController],
  providers: [StockReservationsService],
})
export class ExternalApiModule {}
