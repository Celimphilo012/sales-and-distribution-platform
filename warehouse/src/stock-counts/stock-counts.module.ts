import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { LocationsModule } from '../locations/locations.module';
import { StockAdjustmentsModule } from '../stock-adjustments/stock-adjustments.module';
import { StockCountsController } from './stock-counts.controller';
import { StockCountsService } from './stock-counts.service';

@Module({
  imports: [ProductsModule, LocationsModule, StockAdjustmentsModule],
  controllers: [StockCountsController],
  providers: [StockCountsService],
})
export class StockCountsModule {}
