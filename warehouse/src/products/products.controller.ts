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
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ProductsService } from './products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { ListProductsQueryDto } from './dto/list-products-query.dto';

@ApiTags('products')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Query() query: ListProductsQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.productsService.findAll(query, user.id);
  }

  @Get(':id')
  @RequirePermissions('catalogue.view')
  findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.productsService.findOne(id, user.id);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Body() dto: CreateProductDto, @CurrentUser() user: AuthenticatedUser) {
    return this.productsService.create(dto, user.id);
  }

  @Patch(':id')
  @RequirePermissions('products.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProductDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.productsService.getExisting(id);
    return this.productsService.update(id, dto, user.id);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  async remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.productsService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.productsService.remove(id, user.id);
  }
}
