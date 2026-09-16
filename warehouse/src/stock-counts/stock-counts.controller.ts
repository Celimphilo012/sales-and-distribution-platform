import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
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
import { StockCountsService } from './stock-counts.service';
import { CreateStockCountDto } from './dto/create-stock-count.dto';
import { SubmitStockCountDto } from './dto/submit-stock-count.dto';
import { ListStockCountsQueryDto } from './dto/list-stock-counts-query.dto';

@ApiTags('inventory-counts')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('inventory.count')
@Controller('inventory/counts')
export class StockCountsController {
  constructor(private readonly stockCountsService: StockCountsService) {}

  @Get()
  findAll(@Query() query: ListStockCountsQueryDto) {
    return this.stockCountsService.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.stockCountsService.getExisting(id);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @Body() dto: CreateStockCountDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    const count = await this.stockCountsService.create(dto, user.id);
    req.auditEntity = 'stock_counts';
    req.auditEntityId = count.id;
    return count;
  }

  @Patch(':id')
  async submit(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SubmitStockCountDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditEntity = 'stock_counts';
    req.auditOldValue = await this.stockCountsService.getExisting(id);
    req.auditAction = 'SUBMIT';
    return this.stockCountsService.submit(id, dto, user.id);
  }
}
