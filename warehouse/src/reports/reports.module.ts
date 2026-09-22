import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { CategoriesModule } from '../categories/categories.module';
import { WorkstreamsModule } from '../workstreams/workstreams.module';
import { WarehousesModule } from '../warehouses/warehouses.module';
import { InventoryModule } from '../inventory/inventory.module';
import { StockAdjustmentsModule } from '../stock-adjustments/stock-adjustments.module';
import { StockCountsModule } from '../stock-counts/stock-counts.module';
import { ReportsController } from './reports.controller';
import { DashboardController } from './dashboard.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [
    ProductsModule,
    CategoriesModule,
    WorkstreamsModule,
    WarehousesModule,
    InventoryModule,
    StockAdjustmentsModule,
    StockCountsModule,
  ],
  controllers: [ReportsController, DashboardController],
  providers: [ReportsService],
})
export class ReportsModule {}
