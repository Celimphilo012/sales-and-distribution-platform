import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { deleteImageFile, imageContentType, imageFilePath } from '../common/uploads/image-storage';
import { CreateProductImageDto } from './dto/create-product-image.dto';
import { UpdateProductImageDto } from './dto/update-product-image.dto';
import { UploadProductImageDto } from './dto/upload-product-image.dto';

export const PRODUCT_IMAGE_UPLOAD_SUBDIR = 'products';

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

  /** Same as `create()`, but for a file uploaded from device storage instead of a pasted URL. */
  async createFromUpload(productId: string, storedFilename: string, dto: UploadProductImageDto) {
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
          storagePath: storedFilename,
          sortOrder: dto.sortOrder ?? 0,
          isPrimary: dto.isPrimary ?? false,
        },
      });
    });
  }

  /** Resolves an uploaded image's bytes for the GET .../file endpoint. 404s for a URL-based image (nothing on disk). */
  async getFile(productId: string, imageId: string): Promise<{ path: string; contentType: string }> {
    const image = await this.getExisting(productId, imageId);
    if (!image.storagePath) {
      throw new NotFoundException(`Image ${imageId} has no uploaded file`);
    }
    return {
      path: imageFilePath(PRODUCT_IMAGE_UPLOAD_SUBDIR, image.storagePath),
      contentType: imageContentType(image.storagePath),
    };
  }

  async update(productId: string, imageId: string, dto: UpdateProductImageDto) {
    const existing = await this.getExisting(productId, imageId);

    // Switching an uploaded image over to a pasted URL — keep the
    // url/storagePath invariant (exactly one set) and clean up the now-
    // orphaned file on disk.
    const clearingStoragePath = dto.url !== undefined && existing.storagePath;

    const updated = await this.prisma.$transaction(async (tx) => {
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
          storagePath: clearingStoragePath ? null : undefined,
          sortOrder: dto.sortOrder,
          isPrimary: dto.isPrimary,
        },
      });
    });

    if (clearingStoragePath && existing.storagePath) {
      deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    }
    return updated;
  }

  async remove(productId: string, imageId: string) {
    const existing = await this.getExisting(productId, imageId);
    // Media rows are not historical/reference data — hard delete is fine.
    await this.prisma.productImage.delete({ where: { id: imageId } });
    if (existing.storagePath) {
      deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    }
    return { id: imageId, deleted: true };
  }
}
