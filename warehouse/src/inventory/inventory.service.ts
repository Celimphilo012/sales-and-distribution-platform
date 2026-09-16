import { BadRequestException, Injectable } from '@nestjs/common';
import { InventoryTransactionType, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { LocationsService } from '../locations/locations.service';
import {
  BucketDelta,
  InventoryBucket,
  resolveBucketDeltas,
} from './inventory-transaction-effects';
import { ListBalancesQueryDto } from './dto/list-balances-query.dto';
import { ListTransactionsQueryDto } from './dto/list-transactions-query.dto';

export interface ApplyTransactionInput {
  type: InventoryTransactionType;
  productId: string;
  quantity: number;
  fromLocationId?: string;
  toLocationId?: string;
  /** Only meaningful for ADJUSTMENT / STOCK_COUNT. Defaults to onHand. */
  bucket?: InventoryBucket;
  reason?: string;
  reference?: string;
  orderId?: string;
  performedBy: string;
}

const ZERO_BUCKETS: Record<InventoryBucket, number> = {
  onHand: 0,
  reserved: 0,
  damaged: 0,
  lost: 0,
  expired: 0,
};

type BucketIncrementInput = Partial<Record<InventoryBucket, { increment: number }>>;

// Structurally compatible with both InventoryBalanceUpdateInput (used by
// `update`) and InventoryBalanceUpdateManyMutationInput (used by
// `updateMany`) — both accept `{ <field>: { increment } }` for numeric
// columns, so one helper covers both call sites below.
function updateInputFor(bucket: InventoryBucket, delta: number): BucketIncrementInput {
  switch (bucket) {
    case 'onHand':
      return { onHand: { increment: delta } };
    case 'reserved':
      return { reserved: { increment: delta } };
    case 'damaged':
      return { damaged: { increment: delta } };
    case 'lost':
      return { lost: { increment: delta } };
    case 'expired':
      return { expired: { increment: delta } };
  }
}

function createInputFor(
  productId: string,
  locationId: string,
  bucket: InventoryBucket,
  delta: number,
): Prisma.InventoryBalanceUncheckedCreateInput {
  const buckets = { ...ZERO_BUCKETS, [bucket]: delta };
  return {
    productId,
    locationId,
    onHand: buckets.onHand,
    reserved: buckets.reserved,
    damaged: buckets.damaged,
    lost: buckets.lost,
    expired: buckets.expired,
  };
}

/**
 * Owns inventory_balances and inventory_transactions. This is the ONLY
 * service in the codebase permitted to write inventory_balances (rule 2) —
 * every other module (receiving, transfers, counts, orders/fulfilment in
 * later phases) must call applyTransaction() rather than touching Prisma's
 * `inventoryBalance` model directly. A DB trigger (see the
 * step2b_inventory_ledger migration) backstops this at the database level
 * too.
 */
@Injectable()
export class InventoryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productsService: ProductsService,
    private readonly locationsService: LocationsService,
  ) {}

  /**
   * Writes one inventory_transactions row (the truth) and the resulting
   * inventory_balances delta(s) (the cache) in a single DB transaction
   * (§H). Both commit or both roll back together.
   */
  async applyTransaction(input: ApplyTransactionInput) {
    if (!Number.isFinite(input.quantity) || input.quantity <= 0) {
      throw new BadRequestException('quantity must be a positive number');
    }

    await this.productsService.getExisting(input.productId);
    const locationIds = [input.fromLocationId, input.toLocationId].filter(
      (id): id is string => Boolean(id),
    );
    for (const locationId of locationIds) {
      await this.locationsService.getExisting(locationId);
    }

    const deltas = resolveBucketDeltas(input);

    return this.prisma.$transaction(async (tx) => {
      // Lifts the DB trigger's write guard for this transaction. Unlike
      // Postgres's `SET LOCAL` (transaction-scoped, auto-reset at
      // COMMIT/ROLLBACK), MySQL/MariaDB session variables are
      // connection-scoped and survive both COMMIT and ROLLBACK — so we
      // must explicitly clear it in `finally` before this dedicated
      // connection goes back to Prisma's pool, or a later unrelated query
      // reusing that connection would inherit the flag.
      await tx.$executeRaw`SET @allow_balance_write = 1`;
      try {
        const transaction = await tx.inventoryTransaction.create({
          data: {
            type: input.type,
            productId: input.productId,
            fromLocationId: input.fromLocationId ?? null,
            toLocationId: input.toLocationId ?? null,
            quantity: input.quantity,
            reason: input.reason,
            reference: input.reference,
            orderId: input.orderId,
            performedBy: input.performedBy,
          },
        });

        for (const delta of deltas) {
          await this.applyBalanceDelta(tx, input.productId, delta);
        }

        return transaction;
      } finally {
        await tx.$executeRaw`SET @allow_balance_write = NULL`;
      }
    });
  }

  /**
   * Deliberately NOT `upsert()`. Postgres validates CHECK constraints on
   * the speculatively-proposed INSERT row of an `INSERT ... ON CONFLICT DO
   * UPDATE` *before* conflict resolution redirects it to the UPDATE branch
   * — so a negative delta (e.g. TRANSFER's -30 leg) fails the "on_hand >=
   * 0" check against the raw insert value even when an existing row would
   * happily absorb it via increment. Explicit update-then-create sidesteps
   * that: a real UPDATE is checked against the post-increment row, and a
   * real CREATE is checked against its own starting value — both correct.
   */
  private async applyBalanceDelta(
    tx: Prisma.TransactionClient,
    productId: string,
    delta: BucketDelta,
  ) {
    const updated = await tx.inventoryBalance.updateMany({
      where: { productId, locationId: delta.locationId },
      data: updateInputFor(delta.bucket, delta.delta),
    });
    if (updated.count > 0) return;

    try {
      await tx.inventoryBalance.create({
        data: createInputFor(productId, delta.locationId, delta.bucket, delta.delta),
      });
    } catch (error) {
      // Lost a race with a concurrent first-write for the same (product,
      // location) between the updateMany above and this create — the row
      // exists now, so retry as an update.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        await tx.inventoryBalance.update({
          where: { productId_locationId: { productId, locationId: delta.locationId } },
          data: updateInputFor(delta.bucket, delta.delta),
        });
        return;
      }
      throw error;
    }
  }

  async findBalances(query: ListBalancesQueryDto) {
    const balances = await this.prisma.inventoryBalance.findMany({
      where: {
        productId: query.productId,
        locationId: query.locationId,
        location: query.warehouseId ? { warehouseId: query.warehouseId } : undefined,
      },
      include: {
        product: { select: { id: true, sku: true, name: true, uom: true } },
        location: { select: { id: true, name: true, code: true, warehouseId: true } },
      },
      orderBy: [{ productId: 'asc' }, { locationId: 'asc' }],
    });

    return balances.map((b) => ({
      ...b,
      available: b.onHand.minus(b.reserved),
    }));
  }

  findTransactions(query: ListTransactionsQueryDto) {
    return this.prisma.inventoryTransaction.findMany({
      where: {
        productId: query.productId,
        type: query.type,
        OR: query.locationId
          ? [{ fromLocationId: query.locationId }, { toLocationId: query.locationId }]
          : undefined,
        createdAt: {
          gte: query.from ? new Date(query.from) : undefined,
          lte: query.to ? new Date(query.to) : undefined,
        },
      },
      include: {
        product: { select: { id: true, sku: true, name: true } },
        fromLocation: { select: { id: true, name: true, code: true } },
        toLocation: { select: { id: true, name: true, code: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }
}
