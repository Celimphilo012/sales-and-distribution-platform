import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { PrismaModule } from './common/prisma/prisma.module';
import { AuditInterceptor } from './common/interceptors/audit.interceptor';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { RolesModule } from './roles/roles.module';
import { PermissionsModule } from './permissions/permissions.module';
import { WorkstreamsModule } from './workstreams/workstreams.module';
import { CategoriesModule } from './categories/categories.module';
import { AttributeTypesModule } from './attribute-types/attribute-types.module';
import { ProductsModule } from './products/products.module';
import { ProductImportModule } from './product-import/product-import.module';
import { ProductImagesModule } from './product-images/product-images.module';
import { WarehousesModule } from './warehouses/warehouses.module';
import { LocationsModule } from './locations/locations.module';
import { InventoryModule } from './inventory/inventory.module';
import { ReceivingModule } from './receiving/receiving.module';
import { TransfersModule } from './transfers/transfers.module';
import { StockAdjustmentsModule } from './stock-adjustments/stock-adjustments.module';
import { StockCountsModule } from './stock-counts/stock-counts.module';
import { ApiKeysModule } from './api-keys/api-keys.module';
import { ExternalApiModule } from './external-api/external-api.module';
import { AuditModule } from './audit/audit.module';
import { ReportsModule } from './reports/reports.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    // Registered globally with no default secret: AuthService/AuthGuard
    // pass the access or refresh secret explicitly on every sign/verify
    // call, since the two token types must never share a secret.
    JwtModule.register({ global: true }),
    PrismaModule,
    AuthModule,
    UsersModule,
    RolesModule,
    PermissionsModule,
    WorkstreamsModule,
    CategoriesModule,
    AttributeTypesModule,
    ProductsModule,
    ProductImportModule,
    ProductImagesModule,
    WarehousesModule,
    LocationsModule,
    InventoryModule,
    ReceivingModule,
    TransfersModule,
    StockAdjustmentsModule,
    StockCountsModule,
    ApiKeysModule,
    ExternalApiModule,
    AuditModule,
    ReportsModule,
  ],
  providers: [{ provide: APP_INTERCEPTOR, useClass: AuditInterceptor }],
})
export class AppModule {}
