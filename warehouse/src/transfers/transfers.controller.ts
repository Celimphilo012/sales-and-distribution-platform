import { Body, Controller, HttpCode, HttpStatus, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { TransfersService } from './transfers.service';
import { CreateTransferDto } from './dto/create-transfer.dto';

@ApiTags('inventory-transfers')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('inventory/transfers')
export class TransfersController {
  constructor(private readonly transfersService: TransfersService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @RequirePermissions('inventory.transfer')
  async transfer(
    @Body() dto: CreateTransferDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    const transaction = await this.transfersService.transfer(dto, user.id);
    req.auditEntity = 'inventory_transactions';
    req.auditEntityId = transaction.id;
    return transaction;
  }
}
