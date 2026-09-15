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
import { ProductsService } from '../products/products.service';
import { LocationsService } from '../locations/locations.service';
import { InventoryService } from '../inventory/inventory.service';
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

const ORDER_INCLUDE = {
  customer: { select: { id: true, name: true, phone: true } },
  consultant: { select: { id: true, fullName: true, email: true } },
  items: { include: { product: { select: { id: true, sku: true, name: true, uom: true } } } },
  statusHistory: {
    orderBy: { createdAt: 'asc' as const },
    include: { changedByUser: { select: { id: true, fullName: true } } },
  },
} as const;

interface LineInput {
  productId: string;
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
    private readonly productsService: ProductsService,
    private readonly locationsService: LocationsService,
    private readonly inventoryService: InventoryService,
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
   * APPROVED -> STOCK_RESERVED. Every item's availability is checked
   * BEFORE any InventoryService call so the common case is genuinely
   * all-or-nothing. InventoryService.applyTransaction() is frozen
   * (Phase 1D) and self-contained — it cannot be extended to join an
   * outer DB transaction, so a mid-loop failure (a real race between the
   * pre-check and the reservation calls) is handled by compensating:
   * releasing everything already reserved in this call before rejecting,
   * so the order is never left half-reserved.
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

    const shortfalls: string[] = [];
    for (const alloc of dto.allocations) {
      await this.locationsService.assertLeaf(alloc.locationId);
      const item = itemById.get(alloc.orderItemId)!;
      const balance = await this.prisma.inventoryBalance.findUnique({
        where: { productId_locationId: { productId: item.productId, locationId: alloc.locationId } },
      });
      const onHand = balance ? Number(balance.onHand) : 0;
      const reserved = balance ? Number(balance.reserved) : 0;
      const available = onHand - reserved;
      const required = Number(item.quantityOrdered);
      if (available < required) {
        shortfalls.push(
          `${item.product.sku} at location ${alloc.locationId}: need ${required}, only ${available} available`,
        );
      }
    }
    if (shortfalls.length > 0) {
      throw new ConflictException(`Cannot reserve — insufficient available stock for: ${shortfalls.join('; ')}`);
    }

    const completed: { productId: string; locationId: string; quantity: number }[] = [];
    try {
      for (const alloc of dto.allocations) {
        const item = itemById.get(alloc.orderItemId)!;
        const quantity = Number(item.quantityOrdered);
        await this.inventoryService.applyTransaction({
          type: 'RESERVATION',
          productId: item.productId,
          fromLocationId: alloc.locationId,
          quantity,
          orderId: order.id,
          performedBy: changedBy,
          reason: `Reserved for order ${order.orderNumber}`,
        });
        completed.push({ productId: item.productId, locationId: alloc.locationId, quantity });
      }
    } catch (error) {
      for (const done of completed.reverse()) {
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: done.productId,
          fromLocationId: done.locationId,
          quantity: done.quantity,
          orderId: order.id,
          performedBy: changedBy,
          reason: `Rolled back: reservation failed for order ${order.orderNumber}`,
        });
      }
      throw new ConflictException(
        'Reservation failed partway through and was rolled back — no stock is reserved for this order',
      );
    }

    await this.prisma.$transaction((tx) =>
      this.applyTransition(tx, order.id, 'APPROVED', 'STOCK_RESERVED', changedBy, undefined),
    );

    return this.getExisting(id);
  }

  /**
   * -> CANCELLED from any state the map allows it from (everything up to
   * READY_FOR_DISPATCH; not DISPATCHED onward — enforced by the map
   * itself via applyTransition below, no extra check needed here). If
   * stock is currently reserved for this order (1F extends the
   * "was it STOCK_RESERVED" check to also cover PICKING/PACKED/
   * READY_FOR_DISPATCH, since picking/packing never touch the ledger —
   * the full originally-reserved quantity is still sitting in `reserved`
   * at those stages too), every RESERVATION ledger row tagged with this
   * order is looked up and released before the status changes — the
   * ledger itself is the source of truth for what's reserved and where,
   * so no location needs to be stored on order_items.
   */
  async cancel(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);

    if (ORDER_STATUSES_WITH_ACTIVE_RESERVATION.includes(order.status)) {
      const reservations = await this.prisma.inventoryTransaction.findMany({
        where: { orderId: order.id, type: 'RESERVATION' },
      });
      for (const res of reservations) {
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: res.productId,
          fromLocationId: res.fromLocationId!,
          quantity: Number(res.quantity),
          orderId: order.id,
          performedBy: changedBy,
          reason: `Released on cancellation of order ${order.orderNumber}`,
        });
      }
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
          `Picked quantity for ${item.product.sku} (${entry.pickedQty}) cannot exceed ordered quantity (${ordered})`,
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
          `Packed quantity for ${item.product.sku} (${entry.packedQty}) cannot exceed picked quantity (${picked})`,
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
   * (quantityPacked), read from order_items — dispatch takes no quantity
   * input of its own. Per item, using the SAME leaf location it was
   * reserved at (recovered from the RESERVATION ledger rows, same
   * pattern as pick() and cancel()):
   *   1. RELEASE_RESERVATION(fulfilledQty) — frees the shipped portion
   *      of the reserved bucket.
   *   2. ISSUE(fulfilledQty) — deducts on_hand by the shipped amount.
   *   3. If fulfilledQty < ordered: RELEASE_RESERVATION(remainder) — the
   *      unfulfilled portion is freed too (no backorder is created; a
   *      human decides whether to re-order). Net for a short line:
   *      reserved drops by the FULL ordered qty, on_hand only by the
   *      shipped qty — the unshipped remainder becomes available again.
   * finalStatus is computed BEFORE any ledger call and validated against
   * the map first, so an illegal call has zero side effects.
   */
  async dispatch(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    // Cheap, clear-message guard before computing which of the two
    // possible targets applies — READY_FOR_DISPATCH is the only state
    // either is reachable from, so this is equivalent to (and derived
    // from) the map, not a parallel hardcoded rule.
    if (order.status !== 'READY_FOR_DISPATCH') {
      throw new ConflictException(`Cannot transition order from ${order.status} to DISPATCHED`);
    }

    const reservationLocationByProduct = await this.getReservationLocations(order.id);

    const operations = order.items.map((item) => {
      const ordered = Number(item.quantityOrdered);
      const fulfilledQty = Number(item.quantityPacked);
      if (fulfilledQty > ordered) {
        throw new ConflictException(
          `Packed quantity for ${item.product.sku} exceeds ordered quantity — cannot dispatch`,
        );
      }
      const remainder = round3(ordered - fulfilledQty);
      const locationId = reservationLocationByProduct.get(item.productId);
      if (!locationId) {
        throw new ConflictException(
          `No RESERVATION ledger entry found for ${item.product.sku} on this order — cannot dispatch`,
        );
      }
      return { orderItemId: item.id, productId: item.productId, locationId, fulfilledQty, remainder };
    });

    const finalStatus: OrderStatus = operations.some((op) => op.remainder > 0)
      ? 'PARTIALLY_FULFILLED'
      : 'DISPATCHED';
    assertValidOrderTransition(order.status, finalStatus);

    for (const op of operations) {
      if (op.fulfilledQty > 0) {
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: op.productId,
          fromLocationId: op.locationId,
          quantity: op.fulfilledQty,
          orderId: order.id,
          performedBy: changedBy,
          reason: `Release reserved stock for dispatch of order ${order.orderNumber}`,
        });
        await this.inventoryService.applyTransaction({
          type: 'ISSUE',
          productId: op.productId,
          fromLocationId: op.locationId,
          quantity: op.fulfilledQty,
          orderId: order.id,
          performedBy: changedBy,
          reason: `Dispatch of order ${order.orderNumber}`,
        });
      }
      if (op.remainder > 0) {
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: op.productId,
          fromLocationId: op.locationId,
          quantity: op.remainder,
          orderId: order.id,
          performedBy: changedBy,
          reason: `Release unfulfilled reserved remainder for order ${order.orderNumber}`,
        });
      }
    }

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

  private async buildLineInputs(items: OrderItemInputDto[]): Promise<LineInput[]> {
    return Promise.all(
      items.map(async (item) => {
        const product = await this.productsService.getExisting(item.productId);
        if (product.status !== 'ACTIVE') {
          throw new BadRequestException(`Product ${product.sku} is not active and cannot be ordered`);
        }
        const unitPrice = Number(product.sellingPrice);
        const lineTotal = round2(unitPrice * item.quantity);
        return { productId: item.productId, quantityOrdered: item.quantity, unitPrice, lineTotal };
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

  /**
   * Maps productId -> the leaf location it was reserved at, read from
   * this order's RESERVATION ledger rows (same recovery pattern used by
   * cancel()). Used by pick() and dispatch() so picking/dispatch never
   * need a location as client input — it's already been validated once,
   * at reserve() time.
   */
  private async getReservationLocations(orderId: string): Promise<Map<string, string>> {
    const reservations = await this.prisma.inventoryTransaction.findMany({
      where: { orderId, type: 'RESERVATION' },
      select: { productId: true, fromLocationId: true },
    });
    const byProduct = new Map<string, string>();
    for (const r of reservations) {
      if (r.fromLocationId) byProduct.set(r.productId, r.fromLocationId);
    }
    return byProduct;
  }
}
