import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { InventoryService } from './inventory.service';
import { ListBalancesQueryDto } from './dto/list-balances-query.dto';
import { ListTransactionsQueryDto } from './dto/list-transactions-query.dto';

// Read-only here — receiving/transfers/adjustments/counts write via
// InventoryService.applyTransaction() from their own controllers.
@ApiTags('inventory')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('inventory.view')
@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Get('balances')
  findBalances(@Query() query: ListBalancesQueryDto) {
    return this.inventoryService.findBalances(query);
  }

  @Get('transactions')
  findTransactions(@Query() query: ListTransactionsQueryDto) {
    return this.inventoryService.findTransactions(query);
  }
}
