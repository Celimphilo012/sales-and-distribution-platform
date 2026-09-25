import { Module } from '@nestjs/common';
import { WarehousesModule } from '../warehouses/warehouses.module';
import { WorkstreamManagersModule } from '../workstream-managers/workstream-managers.module';
import { WorkstreamsController } from './workstreams.controller';
import { WorkstreamsService } from './workstreams.service';

@Module({
  imports: [WarehousesModule, WorkstreamManagersModule],
  controllers: [WorkstreamsController],
  providers: [WorkstreamsService],
  exports: [WorkstreamsService],
})
export class WorkstreamsModule {}
