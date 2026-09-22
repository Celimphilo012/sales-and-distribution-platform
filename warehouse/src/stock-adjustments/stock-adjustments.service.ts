import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { AdjustmentBucket, AdjustmentDirection, AdjustmentStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { LocationsService } from '../locations/locations.service';
import { InventoryService } from '../inventory/inventory.service';
import { InventoryBucket } from '../inventory/inventory-transaction-effects';
import { CreateAdjustmentRequestDto } from './dto/create-adjustment-request.dto';
import { ListAdjustmentsQueryDto } from './dto/list-adjustments-query.dto';

const BUCKET_MAP: Record<AdjustmentBucket, InventoryBucket> = {
  ON_HAND: 'onHand',
  RESERVED: 'reserved',
  DAMAGED: 'damaged',
  LOST: 'lost',
  EXPIRED: 'expired',
};

// Used by both the public "request an adjustment" endpoint and
// StockCountsService (which creates one of these per nonzero variance on
// submit) — the shared shape means both entry points get the same
// leaf-location check, the same PENDING-only lifecycle, for free.
export interface CreateAdjustmentRequestInput {
  productId: string;
  locationId: string;
  bucket: AdjustmentBucket;
  delta: number;
  direction: AdjustmentDirection;
  reason: string;
  reference?: string;
  requestedBy: string;
}

const ADJUSTMENT_INCLUDE = {
  product: { select: { id: true, sku: true, name: true } },
  location: { select: { id: true, name: true, code: true } },
  requestedByUser: { select: { id: true, fullName: true, email: true } },
  reviewedByUser: { select: { id: true, fullName: true, email: true } },
} as const;

@Injectable()
export class StockAdjustmentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productsService: ProductsService,
    private readonly locationsService: LocationsService,
    private readonly inventoryService: InventoryService,
  ) {}

  async createRequest(input: CreateAdjustmentRequestInput) {
    await this.productsService.getExisting(input.productId);
    // Stock (and therefore stock corrections) only exists at leaf locations.
    await this.locationsService.assertLeaf(input.locationId);

    return this.prisma.stockAdjustment.create({
      data: {
        productId: input.productId,
        locationId: input.locationId,
        bucket: input.bucket,
        delta: input.delta,
        direction: input.direction,
        reason: input.reason,
        reference: input.reference,
        requestedBy: input.requestedBy,
        // status defaults to PENDING — this call NEVER touches
        // inventory_balances or inventory_transactions.
      },
      include: ADJUSTMENT_INCLUDE,
    });
  }

  async findAll(query: ListAdjustmentsQueryDto) {
    return this.prisma.stockAdjustment.findMany({
      where: { status: query.status },
      include: ADJUSTMENT_INCLUDE,
      orderBy: { requestedAt: 'desc' },
    });
  }

  async getExisting(id: string) {
    const adjustment = await this.prisma.stockAdjustment.findUnique({
      where: { id },
      include: ADJUSTMENT_INCLUDE,
    });
    if (!adjustment) throw new NotFoundException(`Stock adjustment ${id} not found`);
    return adjustment;
  }

  /**
   * The ONLY place a stock adjustment ever moves stock. Everything before
   * this point (request, PENDING) has zero ledger effect (rule 2 /
   * Open Decision #2, resolved).
   */
  async approve(id: string, reviewedBy: string, reviewNote?: string) {
    const adjustment = await this.getExisting(id);

    if (adjustment.status !== 'PENDING') {
      throw new ConflictException(
        `Stock adjustment ${id} is already ${adjustment.status} and cannot be approved again`,
      );
    }
    // Separation of duties: the requester cannot also be the approver.
    if (reviewedBy === adjustment.requestedBy) {
      throw new ForbiddenException(
        'You cannot approve your own adjustment request — a different user must review it',
      );
    }

    const bucket = BUCKET_MAP[adjustment.bucket];
    const isIncrease = adjustment.direction === 'INCREASE';

    // Reused as-is — the frozen Phase 1D part 1 engine is what actually
    // writes the inventory_transactions row and the inventory_balances
    // delta, atomically, with its own DB-trigger backstop.
    const transaction = await this.inventoryService.applyTransaction({
      type: 'ADJUSTMENT',
      productId: adjustment.productId,
      quantity: Number(adjustment.delta),
      bucket,
      toLocationId: isIncrease ? adjustment.locationId : undefined,
      fromLocationId: isIncrease ? undefined : adjustment.locationId,
      reason: adjustment.reason,
      reference: adjustment.reference ?? undefined,
      performedBy: reviewedBy,
    });

    // NOTE: this update is sequential, not nested inside the same DB
    // transaction as applyTransaction() above — InventoryService's
    // $transaction is self-contained (Phase 1D part 1 is frozen; its
    // signature can't be extended to accept an outer `tx`). The ledger
    // write (the actual stock movement, and the thing rule 2 cares about)
    // happens first and is atomic on its own; if this bookkeeping update
    // were to fail, the adjustment would remain visibly PENDING despite
    // stock having moved — a recoverable inconsistency, not a ledger
    // integrity violation, since inventory_transactions is still correct.
    const updated = await this.prisma.stockAdjustment.update({
      where: { id },
      data: {
        status: 'APPROVED',
        reviewedBy,
        reviewedAt: new Date(),
        reviewNote,
      },
      include: ADJUSTMENT_INCLUDE,
    });

    return { ...updated, transactionId: transaction.id };
  }

  async reject(id: string, reviewedBy: string, reviewNote: string) {
    const adjustment = await this.getExisting(id);

    if (adjustment.status !== 'PENDING') {
      throw new ConflictException(
        `Stock adjustment ${id} is already ${adjustment.status} and cannot be rejected`,
      );
    }

    return this.prisma.stockAdjustment.update({
      where: { id },
      data: {
        status: 'REJECTED',
        reviewedBy,
        reviewedAt: new Date(),
        reviewNote,
      },
      include: ADJUSTMENT_INCLUDE,
    });
  }

  /**
   * Reports dashboard — request counts by status over the last [days]
   * (native Prisma `groupBy`), plus the oldest PENDING requests overall
   * (up to 15) so a manager can see what's overdue for review. `oldestPending`
   * is deliberately NOT scoped to [days]: a backlog that's been waiting
   * longer than the period is exactly what "overdue" needs to surface, and
   * `totalPendingCount` (also unscoped) is the true current backlog size —
   * both feed the dashboard's `pendingAdjustments` tile as-is, no duplicate
   * query.
   */
  async getAdjustmentsSummary(days = 7) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const grouped = await this.prisma.stockAdjustment.groupBy({
      by: ['status'],
      where: { requestedAt: { gte: since } },
      _count: { _all: true },
    });
    const byStatus = Object.fromEntries(
      Object.values(AdjustmentStatus).map((status) => [
        status,
        grouped.find((g) => g.status === status)?._count._all ?? 0,
      ]),
    ) as Record<AdjustmentStatus, number>;

    const totalPendingCount = await this.prisma.stockAdjustment.count({ where: { status: 'PENDING' } });

    const oldestPendingRows = await this.prisma.stockAdjustment.findMany({
      where: { status: 'PENDING' },
      include: ADJUSTMENT_INCLUDE,
      orderBy: { requestedAt: 'asc' },
      take: 15,
    });
    const oldestPending = oldestPendingRows.map((a) => ({
      ...a,
      waitingDays: Math.floor((Date.now() - a.requestedAt.getTime()) / (24 * 60 * 60 * 1000)),
    }));

    return { periodDays: days, byStatus, totalPendingCount, oldestPending };
  }
}
