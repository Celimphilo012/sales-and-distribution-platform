import { Module } from '@nestjs/common';
import { InventoryModule } from '../inventory/inventory.module';
import { LocationsModule } from '../locations/locations.module';
import { TransfersController } from './transfers.controller';
import { TransfersService } from './transfers.service';

@Module({
  imports: [InventoryModule, LocationsModule],
  controllers: [TransfersController],
  providers: [TransfersService],
})
export class TransfersModule {}
