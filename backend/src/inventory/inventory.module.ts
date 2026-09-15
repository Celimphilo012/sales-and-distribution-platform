import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { LocationsModule } from '../locations/locations.module';
import { InventoryController } from './inventory.controller';
import { InventoryService } from './inventory.service';

@Module({
  imports: [ProductsModule, LocationsModule],
  controllers: [InventoryController],
  providers: [InventoryService],
  exports: [InventoryService],
})
export class InventoryModule {}
