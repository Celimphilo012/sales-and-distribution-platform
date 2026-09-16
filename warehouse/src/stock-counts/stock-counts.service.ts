import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { LocationsService } from '../locations/locations.service';
import { StockAdjustmentsService } from '../stock-adjustments/stock-adjustments.service';
import { CreateStockCountDto } from './dto/create-stock-count.dto';
import { SubmitStockCountDto } from './dto/submit-stock-count.dto';
import { ListStockCountsQueryDto } from './dto/list-stock-counts-query.dto';

const COUNT_INCLUDE = {
  location: { select: { id: true, name: true, code: true, warehouseId: true } },
  startedByUser: { select: { id: true, fullName: true, email: true } },
  items: {
    include: { product: { select: { id: true, sku: true, name: true } } },
  },
} as const;

@Injectable()
export class StockCountsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productsService: ProductsService,
    private readonly locationsService: LocationsService,
    private readonly stockAdjustmentsService: StockAdjustmentsService,
  ) {}

  /**
   * Starts a count: snapshots expected_qty (current on_hand) for every
   * targeted product at this location. Read-only against inventory —
   * nothing here touches inventory_balances or inventory_transactions.
   */
  async create(dto: CreateStockCountDto, startedBy: string) {
    const location = await this.locationsService.assertLeaf(dto.locationId);

    const targets = dto.productIds
      ? await this.snapshotExplicitProducts(dto.productIds, dto.locationId)
      : await this.snapshotAllBalancesAt(dto.locationId);

    if (targets.length === 0) {
      throw new BadRequestException(
        'Nothing to count: no products specified and no existing inventory balances at this location',
      );
    }

    const count = await this.prisma.$transaction(async (tx) => {
      const created = await tx.stockCount.create({
        data: {
          warehouseId: location.warehouseId,
          locationId: dto.locationId,
          startedBy,
        },
      });
      await tx.stockCountItem.createMany({
        data: targets.map((t) => ({
          stockCountId: created.id,
          productId: t.productId,
          locationId: dto.locationId,
          expectedQty: t.expectedQty,
        })),
      });
      return created;
    });

    return this.getExisting(count.id);
  }

  async findAll(query: ListStockCountsQueryDto) {
    return this.prisma.stockCount.findMany({
      where: { status: query.status, locationId: query.locationId },
      include: COUNT_INCLUDE,
      orderBy: { startedAt: 'desc' },
    });
  }

  async getExisting(id: string) {
    const count = await this.prisma.stockCount.findUnique({
      where: { id },
      include: COUNT_INCLUDE,
    });
    if (!count) throw new NotFoundException(`Stock count ${id} not found`);
    return count;
  }

  /**
   * Submits counted quantities, computes the difference per item, and
   * records the variance. Stock does NOT move here — a nonzero difference
   * only creates a PENDING StockAdjustment (rule 2 stays intact: the count
   * itself never calls InventoryService.applyTransaction()). A manager
   * applying those adjustments through the approve flow is what actually
   * authorizes and moves stock.
   */
  async submit(id: string, dto: SubmitStockCountDto, submittedBy: string) {
    const count = await this.getExisting(id);
    if (count.status !== 'OPEN') {
      throw new ConflictException(`Stock count ${id} is already ${count.status} and cannot be resubmitted`);
    }

    const expectedProductIds = new Set(count.items.map((i) => i.productId));
    const submittedProductIds = new Set(dto.items.map((i) => i.productId));

    const missing = [...expectedProductIds].filter((p) => !submittedProductIds.has(p));
    const extra = [...submittedProductIds].filter((p) => !expectedProductIds.has(p));
    if (missing.length > 0 || extra.length > 0) {
      throw new BadRequestException(
        `Submitted items must exactly match the counted products.` +
          (missing.length ? ` Missing: ${missing.join(', ')}.` : '') +
          (extra.length ? ` Not part of this count: ${extra.join(', ')}.` : ''),
      );
    }

    const itemByProduct = new Map(count.items.map((i) => [i.productId, i]));
    const results = dto.items.map((submitted) => {
      const item = itemByProduct.get(submitted.productId)!;
      const difference = submitted.countedQty - Number(item.expectedQty);
      return { itemId: item.id, productId: submitted.productId, countedQty: submitted.countedQty, difference };
    });

    // Records the variance — this transaction only ever touches
    // stock_count_items/stock_counts, never inventory_balances.
    await this.prisma.$transaction([
      ...results.map((r) =>
        this.prisma.stockCountItem.update({
          where: { id: r.itemId },
          data: { countedQty: r.countedQty, difference: r.difference },
        }),
      ),
      this.prisma.stockCount.update({
        where: { id },
        data: { status: 'SUBMITTED', submittedAt: new Date() },
      }),
    ]);

    // Approval is the authorization: each nonzero variance becomes a
    // PENDING request through the exact same path (and the exact same
    // leaf-location check) as a manually-requested adjustment.
    const createdAdjustmentIds: string[] = [];
    for (const r of results) {
      if (r.difference === 0) continue;
      const adjustment = await this.stockAdjustmentsService.createRequest({
        productId: r.productId,
        locationId: count.locationId,
        bucket: 'ON_HAND',
        delta: Math.abs(r.difference),
        direction: r.difference > 0 ? 'INCREASE' : 'DECREASE',
        reason: 'stock count',
        reference: count.id,
        requestedBy: submittedBy,
      });
      createdAdjustmentIds.push(adjustment.id);
    }

    return { ...(await this.getExisting(id)), createdAdjustmentIds };
  }

  private async snapshotExplicitProducts(productIds: string[], locationId: string) {
    for (const productId of productIds) {
      await this.productsService.getExisting(productId);
    }
    const balances = await this.prisma.inventoryBalance.findMany({
      where: { locationId, productId: { in: productIds } },
      select: { productId: true, onHand: true },
    });
    const balanceByProduct = new Map(balances.map((b) => [b.productId, b.onHand]));
    return productIds.map((productId) => ({
      productId,
      expectedQty: balanceByProduct.get(productId) ?? 0,
    }));
  }

  private async snapshotAllBalancesAt(locationId: string) {
    const balances = await this.prisma.inventoryBalance.findMany({
      where: { locationId },
      select: { productId: true, onHand: true },
    });
    return balances.map((b) => ({ productId: b.productId, expectedQty: b.onHand }));
  }
}
