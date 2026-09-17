import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, ProductStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CategoriesService } from '../categories/categories.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { ListProductsQueryDto } from './dto/list-products-query.dto';

const PRODUCT_INCLUDE = {
  category: {
    select: {
      id: true,
      name: true,
      workstreamId: true,
      workstream: { select: { id: true, name: true, code: true } },
    },
  },
  images: { orderBy: { sortOrder: 'asc' as const } },
};

@Injectable()
export class ProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly categoriesService: CategoriesService,
  ) {}

  findAll(query: ListProductsQueryDto) {
    const where: Prisma.ProductWhereInput = {
      categoryId: query.categoryId,
      status: query.status ?? (query.includeInactive ? undefined : ProductStatus.ACTIVE),
      // Product has no workstream_id of its own — a product's workstream is
      // implied by its category's, so filtering goes through the relation.
      category: query.workstreamId ? { workstreamId: query.workstreamId } : undefined,
    };

    if (query.search) {
      // No `mode: 'insensitive'` on MySQL/MariaDB — that filter option is
      // Postgres-only in Prisma. MySQL's default utf8mb4_*_ci collation
      // already makes LIKE/contains case-insensitive, so plain `contains`
      // has the same effect here.
      where.OR = [{ sku: { contains: query.search } }, { name: { contains: query.search } }];
    }

    return this.prisma.product.findMany({
      where,
      include: PRODUCT_INCLUDE,
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const product = await this.prisma.product.findUnique({
      where: { id },
      include: PRODUCT_INCLUDE,
    });
    if (!product) throw new NotFoundException(`Product ${id} not found`);
    return product;
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  async create(dto: CreateProductDto) {
    await this.categoriesService.getExisting(dto.categoryId);

    const existingSku = await this.prisma.product.findUnique({ where: { sku: dto.sku } });
    if (existingSku) throw new ConflictException('A product with this SKU already exists');

    return this.prisma.product.create({
      data: {
        sku: dto.sku,
        name: dto.name,
        description: dto.description,
        categoryId: dto.categoryId,
        sellingPrice: dto.sellingPrice,
        costPrice: dto.costPrice,
        uom: dto.uom,
        minStockLevel: dto.minStockLevel ?? 0,
      },
      include: PRODUCT_INCLUDE,
    });
  }

  async update(id: string, dto: UpdateProductDto) {
    await this.getExisting(id);

    if (dto.categoryId) {
      await this.categoriesService.getExisting(dto.categoryId);
    }

    return this.prisma.product.update({
      where: { id },
      data: {
        name: dto.name,
        description: dto.description,
        categoryId: dto.categoryId,
        sellingPrice: dto.sellingPrice,
        costPrice: dto.costPrice,
        uom: dto.uom,
        minStockLevel: dto.minStockLevel,
        status: dto.status,
      },
      include: PRODUCT_INCLUDE,
    });
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Reference data is soft-deleted (rule 10) — orders/inventory
    // transactions keep a valid historical product reference.
    return this.prisma.product.update({
      where: { id },
      data: { status: ProductStatus.INACTIVE },
      include: PRODUCT_INCLUDE,
    });
  }
}
