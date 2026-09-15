import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { StockAdjustmentsService } from './stock-adjustments.service';
import { CreateAdjustmentRequestDto } from './dto/create-adjustment-request.dto';
import { ApproveAdjustmentDto } from './dto/approve-adjustment.dto';
import { RejectAdjustmentDto } from './dto/reject-adjustment.dto';
import { ListAdjustmentsQueryDto } from './dto/list-adjustments-query.dto';

@ApiTags('inventory-adjustments')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('inventory/adjustments')
export class StockAdjustmentsController {
  constructor(private readonly stockAdjustmentsService: StockAdjustmentsService) {}

  @Get()
  @RequirePermissions('inventory.view')
  findAll(@Query() query: ListAdjustmentsQueryDto) {
    return this.stockAdjustmentsService.findAll(query);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @RequirePermissions('inventory.adjust.request')
  async create(
    @Body() dto: CreateAdjustmentRequestDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    const adjustment = await this.stockAdjustmentsService.createRequest({
      ...dto,
      requestedBy: user.id,
    });
    req.auditEntity = 'stock_adjustments';
    req.auditEntityId = adjustment.id;
    return adjustment;
  }

  @Post(':id/approve')
  @RequirePermissions('inventory.adjust.approve')
  async approve(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ApproveAdjustmentDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditEntity = 'stock_adjustments';
    req.auditOldValue = await this.stockAdjustmentsService.getExisting(id);
    req.auditAction = 'APPROVE';
    return this.stockAdjustmentsService.approve(id, user.id, dto.reviewNote);
  }

  @Post(':id/reject')
  @RequirePermissions('inventory.adjust.approve')
  async reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RejectAdjustmentDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditEntity = 'stock_adjustments';
    req.auditOldValue = await this.stockAdjustmentsService.getExisting(id);
    req.auditAction = 'REJECT';
    return this.stockAdjustmentsService.reject(id, user.id, dto.reviewNote);
  }
}
