import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { CreateProductImageDto } from './dto/create-product-image.dto';
import { UpdateProductImageDto } from './dto/update-product-image.dto';

@Injectable()
export class ProductImagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productsService: ProductsService,
  ) {}

  async findAll(productId: string) {
    await this.productsService.getExisting(productId);
    return this.prisma.productImage.findMany({
      where: { productId },
      orderBy: { sortOrder: 'asc' },
    });
  }

  async getExisting(productId: string, imageId: string) {
    const image = await this.prisma.productImage.findUnique({ where: { id: imageId } });
    if (!image || image.productId !== productId) {
      throw new NotFoundException(`Image ${imageId} not found for product ${productId}`);
    }
    return image;
  }

  async create(productId: string, dto: CreateProductImageDto) {
    await this.productsService.getExisting(productId);

    return this.prisma.$transaction(async (tx) => {
      if (dto.isPrimary) {
        await tx.productImage.updateMany({
          where: { productId },
          data: { isPrimary: false },
        });
      }
      return tx.productImage.create({
        data: {
          productId,
          url: dto.url,
          sortOrder: dto.sortOrder ?? 0,
          isPrimary: dto.isPrimary ?? false,
        },
      });
    });
  }

  async update(productId: string, imageId: string, dto: UpdateProductImageDto) {
    await this.getExisting(productId, imageId);

    return this.prisma.$transaction(async (tx) => {
      if (dto.isPrimary) {
        await tx.productImage.updateMany({
          where: { productId, id: { not: imageId } },
          data: { isPrimary: false },
        });
      }
      return tx.productImage.update({
        where: { id: imageId },
        data: {
          url: dto.url,
          sortOrder: dto.sortOrder,
          isPrimary: dto.isPrimary,
        },
      });
    });
  }

  async remove(productId: string, imageId: string) {
    await this.getExisting(productId, imageId);
    // Media rows are not historical/reference data — hard delete is fine.
    await this.prisma.productImage.delete({ where: { id: imageId } });
    return { id: imageId, deleted: true };
  }
}
