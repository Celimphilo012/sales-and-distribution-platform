import { Module } from '@nestjs/common';
import { WarehouseApiModule } from '../warehouse-api/warehouse-api.module';
import { WarehouseLocationsController } from './warehouse-locations.controller';
import { WarehouseLocationsService } from './warehouse-locations.service';

@Module({
  imports: [WarehouseApiModule],
  controllers: [WarehouseLocationsController],
  providers: [WarehouseLocationsService],
})
export class WarehouseLocationsModule {}
