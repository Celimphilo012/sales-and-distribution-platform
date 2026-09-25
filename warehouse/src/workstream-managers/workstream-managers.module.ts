import { Module } from '@nestjs/common';
import { WorkstreamManagersController } from './workstream-managers.controller';
import { MyWorkstreamsController } from './my-workstreams.controller';
import { WorkstreamManagersService } from './workstream-managers.service';

// Deliberately imports nothing but the (global) PrismaModule — see
// WorkstreamManagersService's own comment on `assign()`. This lets
// WorkstreamsModule/CategoriesModule/ProductsModule all import THIS module
// for read-scoping without a circular dependency back.
@Module({
  controllers: [WorkstreamManagersController, MyWorkstreamsController],
  providers: [WorkstreamManagersService],
  exports: [WorkstreamManagersService],
})
export class WorkstreamManagersModule {}
