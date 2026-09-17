import { Module } from '@nestjs/common';
import { WorkstreamsModule } from '../workstreams/workstreams.module';
import { CategoriesController } from './categories.controller';
import { CategoriesService } from './categories.service';

@Module({
  imports: [WorkstreamsModule],
  controllers: [CategoriesController],
  providers: [CategoriesService],
  exports: [CategoriesService],
})
export class CategoriesModule {}
