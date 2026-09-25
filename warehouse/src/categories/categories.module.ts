import { Module } from '@nestjs/common';
import { WorkstreamsModule } from '../workstreams/workstreams.module';
import { WorkstreamManagersModule } from '../workstream-managers/workstream-managers.module';
import { CategoriesController } from './categories.controller';
import { CategoriesService } from './categories.service';

@Module({
  imports: [WorkstreamsModule, WorkstreamManagersModule],
  controllers: [CategoriesController],
  providers: [CategoriesService],
  exports: [CategoriesService],
})
export class CategoriesModule {}
