import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
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

// One MariaDB CHECK constraint per bucket (see the step2b_inventory_ledger
// migration) — the database's own backstop against a bucket going negative,
// on top of the DB-write guard trigger. No caller currently pre-validates
// sufficient balance before writing (unlike the external reservation API's
// own "available" check), so this constraint is the ONLY thing stopping an
// over-issue/over-decrement for RECEIVE/ISSUE/TRANSFER/ADJUSTMENT/DAMAGED/
// LOST alike — every one of them can hit this.
const NONNEG_CONSTRAINT_BUCKETS: Record<string, InventoryBucket> = {
  inventory_balances_on_hand_nonneg: 'onHand',
  inventory_balances_reserved_nonneg: 'reserved',
  inventory_balances_damaged_nonneg: 'damaged',
  inventory_balances_lost_nonneg: 'lost',
  inventory_balances_expired_nonneg: 'expired',
};

const BUCKET_LABELS: Record<InventoryBucket, string> = {
  onHand: 'on-hand',
  reserved: 'reserved',
  damaged: 'damaged',
  lost: 'lost',
  expired: 'expired',
};

/**
 * Translates the raw MariaDB/Prisma error from a `..._nonneg` CHECK
 * constraint violation into a clean, human `ConflictException` — instead of
 * letting the engine's connector error (constraint name, SQLSTATE, raw SQL)
 * leak into the API response as an uncaught 500. Never returns; rethrows
 * whatever it was given untouched if it isn't one of these constraints.
 */
function translateBalanceConstraintViolation(error: unknown): never {
  const message = error instanceof Error ? error.message : String(error);
  for (const [constraint, bucket] of Object.entries(NONNEG_CONSTRAINT_BUCKETS)) {
    if (message.includes(constraint)) {
      throw new ConflictException(
        `This would take the ${BUCKET_LABELS[bucket]} quantity below zero at this location — there isn't enough stock there to do this.`,
      );
    }
  }
  throw error;
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
    try {
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
    } catch (error) {
      // Any of the three writes above (the updateMany, the create, or the
      // P2002 retry's update) can hit a `..._nonneg` CHECK constraint —
      // translate it into a clean error instead of leaking the raw one.
      translateBalanceConstraintViolation(error);
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

  /**
   * Reports dashboard — every ACTIVE product whose total on-hand across
   * ACTIVE leaf locations is below its min_stock_level, ordered worst-short
   * first. Every `inventory_balances` row is already at a leaf by
   * construction (`assertLeaf()` on every write via `applyTransaction`), so
   * the only extra filter needed is the location's own `is_active`.
   *
   * The inner subquery aggregates on_hand PER PRODUCT in SQL (a `LEFT JOIN`
   * so a product with zero balance rows still gets a 0, matching "SUM over
   * an empty set is 0" — a product with no stock anywhere and a positive
   * min level correctly counts as low stock). The comparison against
   * min_stock_level happens in the outer query, not in application code —
   * no full-table fetch, no summing in JS.
   */
  async getLowStockProducts() {
    const rows = await this.prisma.$queryRaw<
      { id: string; sku: string; name: string; minStockLevel: string; onHand: string }[]
    >`
      SELECT x.id, x.sku, x.name, x.min_stock_level AS minStockLevel, x.on_hand AS onHand
      FROM (
        SELECT p.id, p.sku, p.name, p.min_stock_level,
               COALESCE(s.total_on_hand, 0) AS on_hand
        FROM products p
        LEFT JOIN (
          SELECT ib.product_id, SUM(ib.on_hand) AS total_on_hand
          FROM inventory_balances ib
          INNER JOIN locations l ON l.id = ib.location_id AND l.is_active = 1
          GROUP BY ib.product_id
        ) s ON s.product_id = p.id
        WHERE p.status = 'ACTIVE'
      ) x
      WHERE x.on_hand < x.min_stock_level
      ORDER BY (x.min_stock_level - x.on_hand) DESC
    `;

    return rows.map((r) => {
      const onHand = Number(r.onHand);
      const minStockLevel = Number(r.minStockLevel);
      return {
        productId: r.id,
        sku: r.sku,
        name: r.name,
        onHand,
        minStockLevel,
        shortfall: minStockLevel - onHand,
      };
    });
  }

  /**
   * Reports dashboard — total value of on-hand stock (ACTIVE products only,
   * cost_price required) plus the 5 highest-value products. Products with a
   * null cost_price are excluded from the total (never treated as 0) and
   * counted separately so the dashboard can disclose the gap honestly.
   * Both the total and the top-5 ranking are computed in SQL.
   */
  async getInventoryValuation() {
    const productBalanceCte = Prisma.sql`
      SELECT p.id, p.sku, p.name, p.cost_price, COALESCE(s.total_on_hand, 0) AS on_hand
      FROM products p
      LEFT JOIN (
        SELECT ib.product_id, SUM(ib.on_hand) AS total_on_hand
        FROM inventory_balances ib
        INNER JOIN locations l ON l.id = ib.location_id AND l.is_active = 1
        GROUP BY ib.product_id
      ) s ON s.product_id = p.id
      WHERE p.status = 'ACTIVE' AND p.cost_price IS NOT NULL
    `;

    const [totalRow] = await this.prisma.$queryRaw<{ total: string | null }[]>`
      SELECT SUM(x.on_hand * x.cost_price) AS total FROM (${productBalanceCte}) x
    `;

    const topRows = await this.prisma.$queryRaw<
      { id: string; sku: string; name: string; onHand: string; costPrice: string; value: string }[]
    >`
      SELECT x.id, x.sku, x.name, x.on_hand AS onHand, x.cost_price AS costPrice,
             (x.on_hand * x.cost_price) AS value
      FROM (${productBalanceCte}) x
      ORDER BY value DESC
      LIMIT 5
    `;

    const excludedProductCount = await this.prisma.product.count({
      where: { status: 'ACTIVE', costPrice: null },
    });

    return {
      total: Number(totalRow?.total ?? 0),
      excludedProductCount,
      topProducts: topRows.map((r) => ({
        productId: r.id,
        sku: r.sku,
        name: r.name,
        onHand: Number(r.onHand),
        costPrice: Number(r.costPrice),
        value: Number(r.value),
      })),
    };
  }

  /**
   * Reports dashboard — transaction counts by type over the last [days]
   * (native Prisma `groupBy`, a DB-level aggregate), plus the most recent 15
   * transactions overall as a "recent activity" feed. The feed is
   * deliberately NOT scoped to [days]: a quiet week would leave it empty and
   * defeat its purpose, unlike the period counts which measure throughput.
   */
  async getStockMovementSummary(days = 7) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const grouped = await this.prisma.inventoryTransaction.groupBy({
      by: ['type'],
      where: { createdAt: { gte: since } },
      _count: { _all: true },
    });
    const byType = Object.fromEntries(
      Object.values(InventoryTransactionType).map((type) => [
        type,
        grouped.find((g) => g.type === type)?._count._all ?? 0,
      ]),
    ) as Record<InventoryTransactionType, number>;

    const recentActivity = await this.prisma.inventoryTransaction.findMany({
      include: {
        product: { select: { id: true, sku: true, name: true } },
        fromLocation: { select: { id: true, name: true, code: true } },
        toLocation: { select: { id: true, name: true, code: true } },
        performedByUser: { select: { id: true, fullName: true, email: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 15,
    });

    return { periodDays: days, byType, recentActivity };
  }
}
