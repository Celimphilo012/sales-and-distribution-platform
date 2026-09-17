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
import { WorkstreamsService } from './workstreams.service';
import { CreateWorkstreamDto } from './dto/create-workstream.dto';
import { UpdateWorkstreamDto } from './dto/update-workstream.dto';
import { ListWorkstreamsQueryDto } from './dto/list-workstreams-query.dto';

// Catalogue-organization layer (Warehouse -> Workstream -> Category ->
// sub-category -> Product) — gated with the SAME permissions as
// categories/products: `catalogue.view` to read, `products.manage` to
// create/edit/deactivate. Purely organizational — never read by inventory/
// ledger code.
@ApiTags('workstreams')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('workstreams')
export class WorkstreamsController {
  constructor(private readonly workstreamsService: WorkstreamsService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Query() query: ListWorkstreamsQueryDto) {
    return this.workstreamsService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions('catalogue.view')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.workstreamsService.findOne(id);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Body() dto: CreateWorkstreamDto) {
    return this.workstreamsService.create(dto);
  }

  @Patch(':id')
  @RequirePermissions('products.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateWorkstreamDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    return this.workstreamsService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  async remove(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.workstreamsService.remove(id);
  }
}
