import { Module } from '@nestjs/common';
import { ProductsModule } from '../products/products.module';
import { CategoriesModule } from '../categories/categories.module';
import { WorkstreamsModule } from '../workstreams/workstreams.module';
import { AttributeTypesModule } from '../attribute-types/attribute-types.module';
import { WarehousesModule } from '../warehouses/warehouses.module';
import { ProductImportController } from './product-import.controller';
import { ProductImportService } from './product-import.service';
import { ProductImportSessionStore } from './product-import-session.store';

@Module({
  // Explicit imports for every service ProductImportService injects — Nest
  // doesn't re-export a module's own imports (e.g. importing ProductsModule
  // alone wouldn't hand us WarehousesService, since CategoriesModule ->
  // WorkstreamsModule -> WarehousesModule is a chain of PRIVATE imports,
  // each module only exporting its own service).
  imports: [ProductsModule, CategoriesModule, WorkstreamsModule, AttributeTypesModule, WarehousesModule],
  controllers: [ProductImportController],
  providers: [ProductImportService, ProductImportSessionStore],
})
export class ProductImportModule {}
