import { Module } from '@nestjs/common';
import { CustomersModule } from '../customers/customers.module';
import { WarehouseApiModule } from '../warehouse-api/warehouse-api.module';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [CustomersModule, WarehouseApiModule],
  controllers: [OrdersController],
  providers: [OrdersService],
})
export class OrdersModule {}
