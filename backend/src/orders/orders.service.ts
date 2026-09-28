import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CustomersService } from '../customers/customers.service';
import { WarehouseApiClient } from '../warehouse-api/warehouse-api.client';
import { WarehouseStockLine } from '../warehouse-api/warehouse-api.types';
import {
  assertValidOrderTransition,
  ORDER_STATUSES_WITH_ACTIVE_RESERVATION,
} from './order-status-transitions';
import { CreateOrderDto } from './dto/create-order.dto';
import { UpdateOrderDto } from './dto/update-order.dto';
import { OrderItemInputDto } from './dto/order-item-input.dto';
import { ReserveOrderDto } from './dto/reserve-order.dto';
import { ListOrdersQueryDto } from './dto/list-orders-query.dto';
import { PickOrderDto } from './dto/pick-order.dto';
import { PackOrderDto } from './dto/pack-order.dto';

// items has no `product` relation to include any more (§A2: no FKs across
// the database boundary — the product lives in warehouse_db). Order lines
// carry their own catalogue snapshot (productName/unitPrice/lineTotal, set
// by buildLineInputs() from the warehouse) plus reservedLocationId (set by
// reserve()).
const ORDER_INCLUDE = {
  customer: { select: { id: true, name: true, phone: true } },
  consultant: { select: { id: true, fullName: true, email: true } },
  items: true,
  statusHistory: {
    orderBy: { createdAt: 'asc' as const },
    include: { changedByUser: { select: { id: true, fullName: true } } },
  },
} as const;

interface LineInput {
  productId: string;
  productName: string;
  quantityOrdered: number;
  unitPrice: number;
  lineTotal: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;
const round3 = (n: number) => Math.round(n * 1000) / 1000;

function generateOrderNumberCandidate(): string {
  const datePart = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const randomPart = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `ORD-${datePart}-${randomPart}`;
}

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly customersService: CustomersService,
    private readonly warehouseApi: WarehouseApiClient,
  ) {}

  /**
   * Same shape of check PermissionGuard does, reused here because
   * `orders.view_team` widens what GET /orders returns beyond what a
   * single required-permission-key route can express (the guard is
   * AND-only across its declared keys) — see OrdersController.
   */
  async hasPermission(userId: string, key: string): Promise<boolean> {
    const grant = await this.prisma.rolePermission.findFirst({
      where: { role: { userRoles: { some: { userId } } }, permission: { key } },
    });
    return Boolean(grant);
  }

  findAll(query: ListOrdersQueryDto, scopeToUserId?: string) {
    return this.prisma.order.findMany({
      where: { status: query.status, customerId: query.customerId, consultantId: scopeToUserId },
      include: ORDER_INCLUDE,
      orderBy: { createdAt: 'desc' },
    });
  }

  async getExisting(id: string) {
    const order = await this.prisma.order.findUnique({ where: { id }, include: ORDER_INCLUDE });
    if (!order) throw new NotFoundException(`Order ${id} not found`);
    return order;
  }

  /** Enforces orders.view_own scoping: an order outside the caller's own is reported as not-found, not forbidden. */
  async findOneScoped(id: string, scopeToUserId?: string) {
    const order = await this.getExisting(id);
    if (scopeToUserId && order.consultantId !== scopeToUserId) {
      throw new NotFoundException(`Order ${id} not found`);
    }
    return order;
  }

  async create(dto: CreateOrderDto, consultantId: string) {
    await this.customersService.getExisting(dto.customerId);
    const lineInputs = await this.buildLineInputs(dto.items);
    const total = round2(lineInputs.reduce((sum, i) => sum + i.lineTotal, 0));
    const orderNumber = await this.generateUniqueOrderNumber();

    const orderId = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          orderNumber,
          customerId: dto.customerId,
          consultantId,
          deliveryInfo: dto.deliveryInfo,
          total,
          items: { create: lineInputs },
        },
      });
      await tx.orderStatusHistory.create({
        data: { orderId: order.id, fromStatus: null, toStatus: 'DRAFT', changedBy: consultantId, note: 'Order created' },
      });
      return order.id;
    });

    return this.getExisting(orderId);
  }

  /** DRAFT-only, owner-only (rule: "and only the owner (consultant_id) may edit own draft"). */
  async update(id: string, dto: UpdateOrderDto, userId: string) {
    const order = await this.getExisting(id);
    if (order.status !== 'DRAFT') {
      throw new ConflictException('Only DRAFT orders can be edited');
    }
    if (order.consultantId !== userId) {
      throw new ForbiddenException("Only the order's owner can edit their own draft");
    }

    let lineInputs: LineInput[] | undefined;
    let total: number | undefined;
    if (dto.items) {
      lineInputs = await this.buildLineInputs(dto.items);
      total = round2(lineInputs.reduce((sum, i) => sum + i.lineTotal, 0));
    }

    await this.prisma.$transaction(async (tx) => {
      if (lineInputs) {
        await tx.orderItem.deleteMany({ where: { orderId: id } });
        await tx.orderItem.createMany({ data: lineInputs.map((i) => ({ ...i, orderId: id })) });
      }
      await tx.order.update({
        where: { id },
        data: { deliveryInfo: dto.deliveryInfo, total },
      });
    });

    return this.getExisting(id);
  }

  /** DRAFT -> SUBMITTED -> PENDING_APPROVAL: one user action, two ledger hops, two history rows. */
  async submit(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction(async (tx) => {
      await this.applyTransition(tx, order.id, order.status, 'SUBMITTED', changedBy, note);
      await this.applyTransition(tx, order.id, 'SUBMITTED', 'PENDING_APPROVAL', changedBy, note);
    });
    return this.getExisting(id);
  }

  async approve(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'APPROVED', changedBy, note),
    );
    return this.getExisting(id);
  }

  async reject(id: string, changedBy: string, note: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'REJECTED', changedBy, note),
    );
    return this.getExisting(id);
  }

  /**
   * APPROVED -> STOCK_RESERVED. Calls the warehouse's
   * `POST /api/v1/stock/reserve` with reference = this order's id (so a
   * client retry after a network blip re-plays the SAME reservation
   * instead of doubling it) and one line per allocation. The warehouse
   * itself guarantees all-or-none for the batch (§A2) — this method only
   * has to branch on its discriminator:
   *   - `success: true`  -> record each line's reservedLocationId (needed
   *     verbatim by dispatch()'s issue() call later, since no local ledger
   *     exists to recover it from) and advance to STOCK_RESERVED, all in
   *     one local transaction.
   *   - `success: false` -> a normal business outcome (insufficient
   *     stock), NOT an error from the warehouse's point of view. Nothing
   *     is written locally; the order stays APPROVED; the structured
   *     short-line detail is surfaced to the caller.
   * A network/HTTP-level failure (warehouse unreachable, bad key, wrong
   * scope, ...) throws out of `this.warehouseApi.reserve()` before any of
   * the above runs — the order is left at APPROVED and, since reserve is
   * idempotent on reference, retrying this same call is always safe.
   */
  async reserve(id: string, dto: ReserveOrderDto, changedBy: string) {
    const order = await this.getExisting(id);
    assertValidOrderTransition(order.status, 'STOCK_RESERVED');

    const itemIds = new Set(order.items.map((i) => i.id));
    const allocatedIds = new Set(dto.allocations.map((a) => a.orderItemId));
    const missing = [...itemIds].filter((i) => !allocatedIds.has(i));
    const extra = [...allocatedIds].filter((i) => !itemIds.has(i));
    if (missing.length > 0 || extra.length > 0) {
      throw new BadRequestException(
        `Allocations must cover exactly this order's items.` +
          (missing.length ? ` Missing: ${missing.join(', ')}.` : '') +
          (extra.length ? ` Not part of this order: ${extra.join(', ')}.` : ''),
      );
    }

    const itemById = new Map(order.items.map((i) => [i.id, i]));
    const lines: WarehouseStockLine[] = dto.allocations.map((alloc) => ({
      productId: itemById.get(alloc.orderItemId)!.productId,
      locationId: alloc.locationId,
      quantity: Number(itemById.get(alloc.orderItemId)!.quantityOrdered),
    }));

    // The label is what warehouse packers see on their packing list (the order id alone means nothing to them).
    const result = await this.warehouseApi.reserve(order.id, lines, `${order.orderNumber} · ${order.customer.name}`);

    if (!result.success) {
      const detail = result.shortLines
        .map((l) => `product ${l.productId} at location ${l.locationId}: need ${l.requested}, only ${l.available} available`)
        .join('; ');
      throw new ConflictException(`Cannot reserve — insufficient available stock for: ${detail}`);
    }

    await this.prisma.$transaction(async (tx) => {
      for (const alloc of dto.allocations) {
        await tx.orderItem.update({
          where: { id: alloc.orderItemId },
          data: { reservedLocationId: alloc.locationId },
        });
      }
      await this.applyTransition(tx, order.id, 'APPROVED', 'STOCK_RESERVED', changedBy, undefined);
    });

    return this.getExisting(id);
  }

  /**
   * -> CANCELLED from any state the map allows it from (everything up to
   * READY_FOR_DISPATCH; not DISPATCHED onward — enforced by the map
   * itself via applyTransition below, no extra check needed here).
   *
   * For an order with an active reservation, calls the warehouse's
   * `POST /api/v1/stock/release` (reference = order id) BEFORE changing
   * the local status — if the warehouse is unreachable this throws and
   * the order stays in its reserved state, uncancelled, rather than
   * silently forgetting to release. release() is idempotent (an
   * already-released or never-reserved reference is a no-op success), so
   * retrying cancel() is always safe. Cancelling an order with NO active
   * reservation (DRAFT/SUBMITTED/PENDING_APPROVAL/APPROVED) needs no
   * warehouse call at all.
   */
  async cancel(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);

    if (ORDER_STATUSES_WITH_ACTIVE_RESERVATION.includes(order.status)) {
      await this.warehouseApi.release(order.id);
    }

    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'CANCELLED', changedBy, note),
    );
    return this.getExisting(id);
  }

  // -----------------------------------------------------------------
  // Phase 1F: picking, packing, dispatch. Picking/packing are physical
  // confirmations — no ledger event (rule: "No stock bucket changes yet").
  // Only dispatch() calls applyTransaction().
  // -----------------------------------------------------------------

  /** STOCK_RESERVED -> PICKING. Records picked qty per line; never more than ordered. */
  async pick(id: string, dto: PickOrderDto, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    assertValidOrderTransition(order.status, 'PICKING');

    this.assertItemCoverage(order.items, dto.items.map((i) => i.orderItemId));
    const itemById = new Map(order.items.map((i) => [i.id, i]));
    for (const entry of dto.items) {
      const item = itemById.get(entry.orderItemId)!;
      const ordered = Number(item.quantityOrdered);
      if (entry.pickedQty > ordered) {
        throw new BadRequestException(
          `Picked quantity for product ${item.productId} (${entry.pickedQty}) cannot exceed ordered quantity (${ordered})`,
        );
      }
    }

    await this.prisma.$transaction(async (tx) => {
      for (const entry of dto.items) {
        await tx.orderItem.update({
          where: { id: entry.orderItemId },
          data: { quantityPicked: entry.pickedQty },
        });
      }
      await this.applyTransition(tx, order.id, order.status, 'PICKING', changedBy, note);
    });

    return this.getExisting(id);
  }

  /** PICKING -> PACKED. Confirms packed qty per line; never more than picked. */
  async pack(id: string, dto: PackOrderDto, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    assertValidOrderTransition(order.status, 'PACKED');

    this.assertItemCoverage(order.items, dto.items.map((i) => i.orderItemId));
    const itemById = new Map(order.items.map((i) => [i.id, i]));
    for (const entry of dto.items) {
      const item = itemById.get(entry.orderItemId)!;
      const picked = Number(item.quantityPicked);
      if (entry.packedQty > picked) {
        throw new BadRequestException(
          `Packed quantity for product ${item.productId} (${entry.packedQty}) cannot exceed picked quantity (${picked})`,
        );
      }
    }

    await this.prisma.$transaction(async (tx) => {
      for (const entry of dto.items) {
        await tx.orderItem.update({
          where: { id: entry.orderItemId },
          data: { quantityPacked: entry.packedQty },
        });
      }
      await this.applyTransition(tx, order.id, order.status, 'PACKED', changedBy, note);
    });

    return this.getExisting(id);
  }

  /** PACKED -> READY_FOR_DISPATCH. Pure status hop, no quantities involved. */
  async ready(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'READY_FOR_DISPATCH', changedBy, note),
    );
    return this.getExisting(id);
  }

  /**
   * READY_FOR_DISPATCH -> DISPATCHED or PARTIALLY_FULFILLED — the
   * deduction point (Open Decision 1). Ships exactly what was packed
   * (quantityPacked) at the SAME leaf location each item was reserved at
   * (reservedLocationId, set by reserve() — there's no local ledger any
   * more to recover this from). One `POST /api/v1/stock/issue` call
   * handles the whole order: per its contract, every line included is
   * released-then-issued for the given quantity, and every RESERVED line
   * NOT included (because nothing was packed for it) is released in
   * full — exactly the "short pack releases the remainder" behaviour 1F
   * always had, now performed server-side. If literally nothing was
   * packed there is no line to issue at all (the warehouse requires at
   * least one) — release() covers that degenerate case.
   *
   * quantityFulfilled and the final status are set ONLY from the
   * warehouse's response, never guessed locally — an order cannot be
   * reported as DISPATCHED/PARTIALLY_FULFILLED until stock has actually
   * left, and that fact only exists on the warehouse side. A
   * network/HTTP-level failure throws before any local write; issue (and
   * release) are idempotent on reference, so retrying dispatch() is safe.
   */
  async dispatch(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    // Cheap, clear-message guard before the stock effect — READY_FOR_DISPATCH
    // is the only state either DISPATCHED or PARTIALLY_FULFILLED is
    // reachable from, so this is equivalent to (and derived from) the map.
    if (order.status !== 'READY_FOR_DISPATCH') {
      throw new ConflictException(`Cannot transition order from ${order.status} to DISPATCHED`);
    }

    for (const item of order.items) {
      if (!item.reservedLocationId) {
        throw new ConflictException(
          `No reservation location recorded for product ${item.productId} on this order — cannot dispatch`,
        );
      }
    }

    const issueLines: WarehouseStockLine[] = order.items
      .filter((item) => Number(item.quantityPacked) > 0)
      .map((item) => ({
        productId: item.productId,
        locationId: item.reservedLocationId!,
        quantity: Number(item.quantityPacked),
      }));

    let issuedByLine: Map<string, number>;
    if (issueLines.length > 0) {
      const result = await this.warehouseApi.issue(order.id, issueLines);
      issuedByLine = new Map(result.issued.map((l) => [`${l.productId}|${l.locationId}`, l.issued]));
    } else {
      // Nothing was packed for any line — nothing to issue, only to
      // release. `issue` requires at least one line, so use `release`.
      await this.warehouseApi.release(order.id);
      issuedByLine = new Map();
    }

    const operations = order.items.map((item) => {
      const fulfilledQty = issuedByLine.get(`${item.productId}|${item.reservedLocationId}`) ?? 0;
      const ordered = Number(item.quantityOrdered);
      const remainder = round3(ordered - fulfilledQty);
      return { orderItemId: item.id, fulfilledQty, remainder };
    });

    const finalStatus: OrderStatus = operations.some((op) => op.remainder > 0)
      ? 'PARTIALLY_FULFILLED'
      : 'DISPATCHED';
    assertValidOrderTransition(order.status, finalStatus);

    await this.prisma.$transaction(async (tx) => {
      for (const op of operations) {
        await tx.orderItem.update({
          where: { id: op.orderItemId },
          data: { quantityFulfilled: op.fulfilledQty },
        });
      }
      await this.applyTransition(tx, order.id, order.status, finalStatus, changedBy, note);
    });

    return this.getExisting(id);
  }

  /** DISPATCHED or PARTIALLY_FULFILLED -> DELIVERED. No ledger changes — stock already left at dispatch. */
  async deliver(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'DELIVERED', changedBy, note),
    );
    return this.getExisting(id);
  }

  /** DELIVERED -> COMPLETED. */
  async complete(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, order.status, 'COMPLETED', changedBy, note),
    );
    return this.getExisting(id);
  }

  private async applyTransition(
    tx: Prisma.TransactionClient,
    orderId: string,
    from: OrderStatus,
    to: OrderStatus,
    changedBy: string,
    note?: string,
  ) {
    assertValidOrderTransition(from, to);
    await tx.order.update({ where: { id: orderId }, data: { status: to } });
    await tx.orderStatusHistory.create({
      data: { orderId, fromStatus: from, toStatus: to, changedBy, note },
    });
  }

  /**
   * Restores rule 8 across the split (ARCHITECTURE.md §A2 step 5): fetches
   * each product from the warehouse catalogue (WarehouseApiClient.
   * getProduct — throws NotFoundException if the id doesn't exist there
   * at all) and snapshots its CURRENT name + sellingPrice onto the order
   * line — never a client-supplied price. A product that exists but is
   * INACTIVE is rejected with a clear error, same as when the catalogue
   * lived in this database. sellingPrice comes back from the warehouse as
   * a JSON string (§E) — parsed with Number() here, same as every other
   * decimal field crossing that boundary.
   */
  private async buildLineInputs(items: OrderItemInputDto[]): Promise<LineInput[]> {
    return Promise.all(
      items.map(async (item) => {
        const product = await this.warehouseApi.getProduct(item.productId);
        if (product.status !== 'ACTIVE') {
          throw new BadRequestException(`Product ${product.sku} is not active and cannot be ordered`);
        }
        const unitPrice = Number(product.sellingPrice);
        const lineTotal = round2(unitPrice * item.quantity);
        return {
          productId: item.productId,
          productName: product.name,
          quantityOrdered: item.quantity,
          unitPrice,
          lineTotal,
        };
      }),
    );
  }

  private async generateUniqueOrderNumber(): Promise<string> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = generateOrderNumberCandidate();
      const existing = await this.prisma.order.findUnique({ where: { orderNumber: candidate } });
      if (!existing) return candidate;
    }
    throw new ConflictException('Could not generate a unique order number — please retry');
  }

  /** Shared by pick()/pack(): the submitted item set must exactly match the order's items. */
  private assertItemCoverage(orderItems: { id: string }[], providedIds: string[]) {
    const itemIds = new Set(orderItems.map((i) => i.id));
    const providedSet = new Set(providedIds);
    const missing = [...itemIds].filter((i) => !providedSet.has(i));
    const extra = [...providedSet].filter((i) => !itemIds.has(i));
    if (missing.length > 0 || extra.length > 0) {
      throw new BadRequestException(
        `Items must cover exactly this order's items.` +
          (missing.length ? ` Missing: ${missing.join(', ')}.` : '') +
          (extra.length ? ` Not part of this order: ${extra.join(', ')}.` : ''),
      );
    }
  }
}
