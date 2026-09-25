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
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Request, Response } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { createImageMulterOptions } from '../common/uploads/image-storage';
import { ProductImagesService, PRODUCT_IMAGE_UPLOAD_SUBDIR } from './product-images.service';
import { CreateProductImageDto } from './dto/create-product-image.dto';
import { UpdateProductImageDto } from './dto/update-product-image.dto';
import { UploadProductImageDto } from './dto/upload-product-image.dto';

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

  @Post('upload')
  @RequirePermissions('products.manage')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', createImageMulterOptions(PRODUCT_IMAGE_UPLOAD_SUBDIR)))
  async uploadFile(
    @Param('productId', ParseUUIDPipe) productId: string,
    @UploadedFile() file: Express.Multer.File,
    @Body() dto: UploadProductImageDto,
    @Req() req: Request,
  ) {
    req.auditEntity = 'product_images';
    const image = await this.productImagesService.createFromUpload(productId, file.filename, dto);
    req.auditEntityId = image.id;
    return image;
  }

  @Get(':imageId/file')
  @RequirePermissions('catalogue.view')
  async getFile(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Param('imageId', ParseUUIDPipe) imageId: string,
    @Res() res: Response,
  ) {
    const { path, contentType } = await this.productImagesService.getFile(productId, imageId);
    res.setHeader('Content-Type', contentType);
    res.sendFile(path);
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
