import { Module } from '@nestjs/common';
import { WarehouseApiModule } from '../warehouse-api/warehouse-api.module';
import { CatalogueController } from './catalogue.controller';
import { CatalogueService } from './catalogue.service';

@Module({
  imports: [WarehouseApiModule],
  controllers: [CatalogueController],
  providers: [CatalogueService],
})
export class CatalogueModule {}
