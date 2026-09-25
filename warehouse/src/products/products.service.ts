import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { AttributeType, Prisma, ProductStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CategoriesService } from '../categories/categories.service';
import { AttributeTypesService } from '../attribute-types/attribute-types.service';
import { WorkstreamManagersService } from '../workstream-managers/workstream-managers.service';
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
      // One level up only — the catalogue's own nesting rule allows
      // arbitrarily deep categories, but the frontend's "Parent (Sub)"
      // display (products table) only ever needs the immediate parent, not
      // the full ancestor chain.
      parent: { select: { id: true, name: true } },
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
    private readonly workstreamManagersService: WorkstreamManagersService,
  ) {}

  /** [viewerId], when given, narrows the result to only products whose category is in a workstream that viewer is assigned to. */
  async findAll(query: ListProductsQueryDto, viewerId?: string) {
    const workstreamId = await this.effectiveWorkstreamIdFilter(query.workstreamId, viewerId);
    const where: Prisma.ProductWhereInput = {
      categoryId: query.categoryId,
      status: query.status ?? (query.includeInactive ? undefined : ProductStatus.ACTIVE),
      // Product has no workstream_id of its own — a product's workstream is
      // implied by its category's, so filtering goes through the relation.
      category: workstreamId ? { workstreamId } : undefined,
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

    const products = await this.prisma.product.findMany({
      where,
      include: PRODUCT_INCLUDE,
      orderBy: { name: 'asc' },
    });
    return this.attachTotalOnHand(products);
  }

  async getExisting(id: string) {
    const product = await this.prisma.product.findUnique({
      where: { id },
      include: PRODUCT_INCLUDE,
    });
    if (!product) throw new NotFoundException(`Product ${id} not found`);
    const [withTotal] = await this.attachTotalOnHand([product]);
    return withTotal;
  }

  /**
   * Sum of on_hand across every ACTIVE location, batched for a whole result
   * set in ONE groupBy — never N+1, never a full-table fetch summed in JS.
   * Read directly off `inventory_balances` (never written here — rule 2 is
   * about writes; reading another module's table for a display aggregate is
   * the same pattern stock-adjustments/stock-counts/warehouses already use,
   * and avoids a circular module import: InventoryModule already imports
   * ProductsModule, so ProductsModule can't import InventoryModule back).
   */
  private async attachTotalOnHand<T extends { id: string }>(
    products: T[],
  ): Promise<(T & { totalOnHand: number })[]> {
    if (products.length === 0) return [];

    const totals = await this.prisma.inventoryBalance.groupBy({
      by: ['productId'],
      where: { productId: { in: products.map((p) => p.id) }, location: { isActive: true } },
      _sum: { onHand: true },
    });
    const totalByProductId = new Map(totals.map((t) => [t.productId, Number(t._sum.onHand ?? 0)]));

    return products.map((p) => ({ ...p, totalOnHand: totalByProductId.get(p.id) ?? 0 }));
  }

  /** [viewerId], when given, 403s if that viewer is scoped and this product's category's workstream isn't one of theirs. */
  async findOne(id: string, viewerId?: string) {
    const product = await this.getExisting(id);
    if (viewerId) await this.workstreamManagersService.assertScopedAccess(viewerId, product.category!.workstreamId);
    return product;
  }

  /** Same intersection logic as CategoriesService's own private helper — see its doc comment. Duplicated rather than shared since there's no natural common module for these two services to both depend on without adding one just for this. */
  private async effectiveWorkstreamIdFilter(
    explicit: string | undefined,
    viewerId: string | undefined,
  ): Promise<string | { in: string[] } | undefined> {
    if (!viewerId) return explicit;
    const assignedIds = await this.workstreamManagersService.getAssignedWorkstreamIds(viewerId);
    if (assignedIds.length === 0) return explicit;
    if (!explicit) return { in: assignedIds };
    return assignedIds.includes(explicit) ? explicit : { in: [] };
  }

  /**
   * Bulk existing-product lookup by SKU, active or not — used by the
   * product-import feature to tell "update" rows (SKU already exists) from
   * "create" rows across a whole uploaded file in one query instead of one
   * per row. No other caller needs this shape (`findAll`'s filters don't
   * support an arbitrary SKU list), which is why it's its own method rather
   * than overloading `findAll`.
   */
  findManyBySkus(skus: string[]) {
    if (skus.length === 0) return Promise.resolve([]);
    return this.prisma.product.findMany({ where: { sku: { in: skus } }, include: PRODUCT_INCLUDE });
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary — never fetch-and-count in JS. */
  countActive() {
    return this.prisma.product.count({ where: { status: ProductStatus.ACTIVE } });
  }

  async create(dto: CreateProductDto, actingUserId: string) {
    const category = await this.categoriesService.getExisting(dto.categoryId);
    await this.workstreamManagersService.assertScopedAccess(actingUserId, category.workstreamId);

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

      return product.id;
    }).then((productId) => this.getExisting(productId));
  }

  async update(id: string, dto: UpdateProductDto, actingUserId: string) {
    const existing = await this.getExisting(id);
    // Scoped to the product's CURRENT workstream (via its category) always
    // — moving it to a new category (below) additionally requires scope
    // over the DESTINATION category's workstream too.
    await this.workstreamManagersService.assertScopedAccess(actingUserId, existing.category!.workstreamId);

    if (dto.categoryId) {
      const newCategory = await this.categoriesService.getExisting(dto.categoryId);
      await this.workstreamManagersService.assertScopedAccess(actingUserId, newCategory.workstreamId);
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

      return id;
    }).then((productId) => this.getExisting(productId));
  }

  async remove(id: string, actingUserId: string) {
    const existing = await this.getExisting(id);
    await this.workstreamManagersService.assertScopedAccess(actingUserId, existing.category!.workstreamId);
    // Reference data is soft-deleted (rule 10) — orders/inventory
    // transactions keep a valid historical product reference.
    await this.prisma.product.update({
      where: { id },
      data: { status: ProductStatus.INACTIVE },
    });
    return this.getExisting(id);
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
