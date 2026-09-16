import { Body, Controller, HttpCode, HttpStatus, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ReceivingService } from './receiving.service';
import { CreateReceivingDto } from './dto/create-receiving.dto';

@ApiTags('inventory-receiving')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('inventory/receiving')
export class ReceivingController {
  constructor(private readonly receivingService: ReceivingService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @RequirePermissions('inventory.receive')
  async receive(
    @Body() dto: CreateReceivingDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    const transaction = await this.receivingService.receive(dto, user.id);
    // This route creates an inventory_transactions row, not a "receiving"
    // row (there is no such table) — point the audit log at what was
    // actually written, not the URL's first segment ("inventory").
    req.auditEntity = 'inventory_transactions';
    req.auditEntityId = transaction.id;
    return transaction;
  }
}
