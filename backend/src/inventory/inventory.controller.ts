import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { InventoryService } from './inventory.service';
import { ListBalancesQueryDto } from './dto/list-balances-query.dto';
import { ListTransactionsQueryDto } from './dto/list-transactions-query.dto';

// Read-only in this part of Phase 1D: inventory_balances/inventory_transactions
// and the InventoryService.applyTransaction() engine that owns them are built
// here, but no HTTP endpoint writes a transaction yet. That arrives with
// receiving/transfers/counts (Phase 1D part 2), which will call
// InventoryService.applyTransaction() the same way this controller reads
// its output.
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
