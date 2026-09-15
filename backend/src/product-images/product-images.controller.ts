import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ProductImagesService } from './product-images.service';
import { CreateProductImageDto } from './dto/create-product-image.dto';
import { UpdateProductImageDto } from './dto/update-product-image.dto';

@ApiTags('product-images')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('products/:productId/images')
export class ProductImagesController {
  constructor(private readonly productImagesService: ProductImagesService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Param('productId', ParseUUIDPipe) productId: string) {
    return this.productImagesService.findAll(productId);
  }

  @Post()
  @RequirePermissions('products.manage')
  async create(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Body() dto: CreateProductImageDto,
    @Req() req: Request,
  ) {
    req.auditEntity = 'product_images';
    const image = await this.productImagesService.create(productId, dto);
    req.auditEntityId = image.id;
    return image;
  }

  @Patch(':imageId')
  @RequirePermissions('products.manage')
  async update(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Param('imageId', ParseUUIDPipe) imageId: string,
    @Body() dto: UpdateProductImageDto,
    @Req() req: Request,
  ) {
    req.auditEntity = 'product_images';
    req.auditOldValue = await this.productImagesService.getExisting(productId, imageId);
    return this.productImagesService.update(productId, imageId, dto);
  }

  @Delete(':imageId')
  @RequirePermissions('products.manage')
  async remove(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Param('imageId', ParseUUIDPipe) imageId: string,
    @Req() req: Request,
  ) {
    req.auditEntity = 'product_images';
    req.auditOldValue = await this.productImagesService.getExisting(productId, imageId);
    return this.productImagesService.remove(productId, imageId);
  }
}
