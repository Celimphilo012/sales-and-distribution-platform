import { Module } from '@nestjs/common';
import { CategoriesModule } from '../categories/categories.module';
import { AttributeTypesModule } from '../attribute-types/attribute-types.module';
import { WorkstreamManagersModule } from '../workstream-managers/workstream-managers.module';
import { ProductsController } from './products.controller';
import { ProductsService } from './products.service';

@Module({
  imports: [CategoriesModule, AttributeTypesModule, WorkstreamManagersModule],
  controllers: [ProductsController],
  providers: [ProductsService],
  exports: [ProductsService],
})
export class ProductsModule {}
