import { Module } from '@nestjs/common';
import { WarehouseApiClient } from './warehouse-api.client';

@Module({
  providers: [WarehouseApiClient],
  exports: [WarehouseApiClient],
})
export class WarehouseApiModule {}
