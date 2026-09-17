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
import { AttributeTypesService } from './attribute-types.service';
import { CreateAttributeTypeDto } from './dto/create-attribute-type.dto';
import { UpdateAttributeTypeDto } from './dto/update-attribute-type.dto';
import { ListAttributeTypesQueryDto } from './dto/list-attribute-types-query.dto';

// The admin-managed type catalog behind product attributes — gated with the
// SAME permissions as categories/products/workstreams: `catalogue.view` to
// read, `products.manage` to create/edit/deactivate. Adding a new type here
// (e.g. "Country of Origin") is how the attribute model stays extensible
// without a code change — the product form picks up new types automatically.
@ApiTags('attribute-types')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('attribute-types')
export class AttributeTypesController {
  constructor(private readonly attributeTypesService: AttributeTypesService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Query() query: ListAttributeTypesQueryDto) {
    return this.attributeTypesService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions('catalogue.view')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.attributeTypesService.findOne(id);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Body() dto: CreateAttributeTypeDto) {
    return this.attributeTypesService.create(dto);
  }

  @Patch(':id')
  @RequirePermissions('products.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAttributeTypeDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.attributeTypesService.getExisting(id);
    return this.attributeTypesService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  async remove(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.attributeTypesService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.attributeTypesService.remove(id);
  }
}
