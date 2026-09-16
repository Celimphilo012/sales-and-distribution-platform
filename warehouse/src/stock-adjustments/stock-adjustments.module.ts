import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { LocationsModule } from '../locations/locations.module';
import { InventoryModule } from '../inventory/inventory.module';
import { StockAdjustmentsController } from './stock-adjustments.controller';
import { StockAdjustmentsService } from './stock-adjustments.service';

@Module({
  imports: [ProductsModule, LocationsModule, InventoryModule],
  controllers: [StockAdjustmentsController],
  providers: [StockAdjustmentsService],
  exports: [StockAdjustmentsService],
})
export class StockAdjustmentsModule {}
