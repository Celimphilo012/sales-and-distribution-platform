import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { AttributeType, Prisma, ProductStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CategoriesService } from '../categories/categories.service';
import { AttributeTypesService } from '../attribute-types/attribute-types.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { ListProductsQueryDto } from './dto/list-products-query.dto';
import { ProductAttributeInputDto } from './dto/product-attribute-input.dto';

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
  // Descriptive metadata only (rule: NOT variants) — never read by
  // inventory/ledger code. Ordered by the attribute type's name so the
  // list is stable regardless of insertion order.
  attributes: {
    include: { attributeType: true },
    orderBy: { attributeType: { name: 'asc' as const } },
  },
};

interface ResolvedAttribute {
  attributeTypeId: string;
  value: string;
}

@Injectable()
export class ProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly categoriesService: CategoriesService,
    private readonly attributeTypesService: AttributeTypesService,
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

    // `?attribute=Colour:Red` — matched by the attribute TYPE's name (not
    // code), split on the FIRST colon so a value containing ":" still works.
    if (query.attribute) {
      const separatorIndex = query.attribute.indexOf(':');
      if (separatorIndex > 0) {
        const name = query.attribute.slice(0, separatorIndex).trim();
        const value = query.attribute.slice(separatorIndex + 1).trim();
        where.attributes = { some: { attributeType: { name }, value } };
      }
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

    const attributes = await this.resolveAttributes(dto.attributes);

    return this.prisma.$transaction(async (tx) => {
      const product = await tx.product.create({
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
      });

      if (attributes?.length) {
        await tx.productAttribute.createMany({
          data: attributes.map((a) => ({ productId: product.id, ...a })),
        });
      }

      return tx.product.findUniqueOrThrow({ where: { id: product.id }, include: PRODUCT_INCLUDE });
    });
  }

  async update(id: string, dto: UpdateProductDto) {
    await this.getExisting(id);

    if (dto.categoryId) {
      await this.categoriesService.getExisting(dto.categoryId);
    }

    const attributes = await this.resolveAttributes(dto.attributes);

    return this.prisma.$transaction(async (tx) => {
      await tx.product.update({
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
      });

      // Only touch attributes when the field was explicitly provided — an
      // omitted `attributes` leaves the existing set untouched; an empty
      // array `[]` deliberately clears it. When provided, it REPLACES the
      // full set (the frontend always resubmits the complete section).
      if (attributes !== undefined) {
        await tx.productAttribute.deleteMany({ where: { productId: id } });
        if (attributes.length) {
          await tx.productAttribute.createMany({
            data: attributes.map((a) => ({ productId: id, ...a })),
          });
        }
      }

      return tx.product.findUniqueOrThrow({ where: { id }, include: PRODUCT_INCLUDE });
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

  /**
   * Validates and normalizes a create/update DTO's `attributes` array:
   * every `attributeTypeId` must exist, at most once each (one value per
   * type — descriptive, not variants), and its value must fit the
   * attribute type's `dataType`. Returns `undefined` when the input itself
   * is `undefined` (caller: "don't touch attributes"), distinct from `[]`
   * ("clear them all").
   */
  private async resolveAttributes(
    inputs: ProductAttributeInputDto[] | undefined,
  ): Promise<ResolvedAttribute[] | undefined> {
    if (inputs === undefined) return undefined;

    const seen = new Set<string>();
    const resolved: ResolvedAttribute[] = [];

    for (const input of inputs) {
      if (seen.has(input.attributeTypeId)) {
        throw new BadRequestException(
          'Duplicate attributeTypeId in attributes — a product has only one value per attribute type',
        );
      }
      seen.add(input.attributeTypeId);

      const attributeType = await this.attributeTypesService.getExisting(input.attributeTypeId);
      resolved.push({
        attributeTypeId: input.attributeTypeId,
        value: this.coerceAttributeValue(attributeType, input.value),
      });
    }

    return resolved;
  }

  private coerceAttributeValue(attributeType: AttributeType, raw: string | number): string {
    if (attributeType.dataType === 'NUMBER') {
      const num = typeof raw === 'number' ? raw : Number(raw);
      if (raw === '' || raw === null || Number.isNaN(num)) {
        throw new BadRequestException(`Attribute "${attributeType.name}" expects a number`);
      }
      // Canonical string form — the same "string" shape Decimal columns
      // already serialize as on read, so this round-trips through JSON
      // identically to how selling_price etc. do.
      return String(num);
    }

    const text = String(raw).trim();
    if (!text) {
      throw new BadRequestException(`Attribute "${attributeType.name}" cannot be empty`);
    }
    return text;
  }
}
