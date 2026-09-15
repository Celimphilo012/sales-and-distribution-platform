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
import { CategoriesModule } from './categories/categories.module';
import { ProductsModule } from './products/products.module';
import { ProductImagesModule } from './product-images/product-images.module';
import { WarehousesModule } from './warehouses/warehouses.module';
import { LocationsModule } from './locations/locations.module';
import { InventoryModule } from './inventory/inventory.module';
import { ReceivingModule } from './receiving/receiving.module';
import { TransfersModule } from './transfers/transfers.module';
import { StockAdjustmentsModule } from './stock-adjustments/stock-adjustments.module';
import { StockCountsModule } from './stock-counts/stock-counts.module';
import { CustomersModule } from './customers/customers.module';
import { OrdersModule } from './orders/orders.module';
import { ReportsModule } from './reports/reports.module';
import { AuditModule } from './audit/audit.module';
import { DashboardModule } from './dashboard/dashboard.module';

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
    CategoriesModule,
    ProductsModule,
    ProductImagesModule,
    WarehousesModule,
    LocationsModule,
    InventoryModule,
    ReceivingModule,
    TransfersModule,
    StockAdjustmentsModule,
    StockCountsModule,
    CustomersModule,
    OrdersModule,
    ReportsModule,
    AuditModule,
    DashboardModule,
  ],
  providers: [{ provide: APP_INTERCEPTOR, useClass: AuditInterceptor }],
})
export class AppModule {}
