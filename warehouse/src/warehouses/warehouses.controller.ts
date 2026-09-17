import {
  Body,
  Controller,
  Delete,
  Get,
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
import { WarehousesService } from './warehouses.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { UpdateWarehouseDto } from './dto/update-warehouse.dto';
import { ListWarehousesQueryDto } from './dto/list-warehouses-query.dto';

// Read routes (list/get) default to `warehouse.structure.view` via the
// class-level decorator; each mutating route overrides it with
// `warehouse.structure.manage` (RequirePermissions is resolved with
// getAllAndOverride, so a method-level decorator replaces the class-level
// one rather than merging with it). `.manage` implies `.view` via the seed
// (ADMIN — the only role with `.manage` — is granted every catalog key), not
// by stacking both keys here.
@ApiTags('warehouses')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('warehouse.structure.view')
@Controller('warehouses')
export class WarehousesController {
  constructor(private readonly warehousesService: WarehousesService) {}

  @Get()
  findAll(@Query() query: ListWarehousesQueryDto) {
    return this.warehousesService.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.warehousesService.findOne(id);
  }

  @Post()
  @RequirePermissions('warehouse.structure.manage')
  create(@Body() dto: CreateWarehouseDto) {
    return this.warehousesService.create(dto);
  }

  @Patch(':id')
  @RequirePermissions('warehouse.structure.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateWarehouseDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.warehousesService.getExisting(id);
    return this.warehousesService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions('warehouse.structure.manage')
  async remove(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.warehousesService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.warehousesService.remove(id);
  }
}
