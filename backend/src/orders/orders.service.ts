import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  NotImplementedException,
} from '@nestjs/common';
import { OrderStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CustomersService } from '../customers/customers.service';
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
// carry only productId + the price snapshot; see OrderItemInputDto for the
// step-5 TODO on restoring a server-side price snapshot and adding a name
// snapshot.
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
  quantityOrdered: number;
  unitPrice: number;
  lineTotal: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

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
   * APPROVED -> STOCK_RESERVED.
   *
   * STUBBED (step 4 of the system split, ARCHITECTURE.md §A2 — step 5
   * TODO): reservation used to check availability and call the in-process
   * InventoryService.applyTransaction() directly. Inventory now lives in
   * warehouse_db, a separate database this app has no transaction with —
   * step 5 rewires this to call the warehouse's
   * `POST /api/v1/stock/reserve` (reference = order id, all-or-none,
   * idempotent) and only advance the order to STOCK_RESERVED on a
   * `success: true` response, compensating via
   * `POST /api/v1/stock/release` on a partial/failed order-side follow-up.
   * The transition itself is validated first so an illegal call (wrong
   * source state) still fails with the normal state-machine error, not
   * this stub.
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

    throw new NotImplementedException(
      'TODO step 5: reserve stock via warehouse POST /api/v1/stock/reserve (reference = this order id) ' +
        'before transitioning this order to STOCK_RESERVED',
    );
  }

  /**
   * -> CANCELLED from any state the map allows it from (everything up to
   * READY_FOR_DISPATCH; not DISPATCHED onward — enforced by the map
   * itself via applyTransition below, no extra check needed here).
   *
   * STUBBED for orders with an active reservation (step 4 of the system
   * split, ARCHITECTURE.md §A2 — step 5 TODO): releasing reserved stock
   * used to look up this order's RESERVATION ledger rows in-process and
   * call InventoryService.applyTransaction() directly. That ledger now
   * lives in warehouse_db — step 5 rewires this to call the warehouse's
   * `POST /api/v1/stock/release` (reference = order id, idempotent,
   * no-op if nothing is reserved) before the status changes. Cancelling
   * an order with NO active reservation (DRAFT/SUBMITTED/
   * PENDING_APPROVAL/APPROVED) needs no stock effect at all and is left
   * fully working — only the stock side effect is stubbed, not the state
   * transition.
   */
  async cancel(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);

    if (ORDER_STATUSES_WITH_ACTIVE_RESERVATION.includes(order.status)) {
      throw new NotImplementedException(
        'TODO step 5: release reserved stock via warehouse POST /api/v1/stock/release ' +
          '(reference = this order id) before cancelling an order with an active reservation',
      );
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
   * deduction point (Open Decision 1).
   *
   * STUBBED (step 4 of the system split, ARCHITECTURE.md §A2 — step 5
   * TODO): dispatch used to read the reservation's leaf location straight
   * off the local RESERVATION ledger rows and call
   * InventoryService.applyTransaction() in-process (RELEASE_RESERVATION
   * then ISSUE per line, per-item remainder released for a short pack).
   * That ledger now lives in warehouse_db — step 5 rewires this to call
   * the warehouse's `POST /api/v1/stock/issue` (reference = order id,
   * one call per order handles the full release-then-issue sequence and
   * partial-fulfilment remainder release server-side, idempotent) and
   * only set quantityFulfilled / advance the status once that call
   * reports success. Deliberately NOT guessing a status or writing
   * quantityFulfilled here — an order cannot be reported as DISPATCHED or
   * PARTIALLY_FULFILLED until stock has actually left, and that fact only
   * exists on the warehouse side.
   */
  async dispatch(id: string, changedBy: string, note?: string) {
    const order = await this.getExisting(id);
    // Cheap, clear-message guard before the stock effect — READY_FOR_DISPATCH
    // is the only state either DISPATCHED or PARTIALLY_FULFILLED is
    // reachable from, so this is equivalent to (and derived from) the map.
    if (order.status !== 'READY_FOR_DISPATCH') {
      throw new ConflictException(`Cannot transition order from ${order.status} to DISPATCHED`);
    }

    throw new NotImplementedException(
      'TODO step 5: dispatch stock via warehouse POST /api/v1/stock/issue (reference = this order id) ' +
        'before recording fulfilled quantities and transitioning this order to DISPATCHED/PARTIALLY_FULFILLED',
    );
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
   * TEMPORARY (step 4 of the system split, ARCHITECTURE.md §A2 — step 5
   * TODO): this used to look up the product in-process (via
   * ProductsService) to snapshot its current selling price server-side
   * and reject inactive products (rule 8: never trust client pricing).
   * The catalogue now lives in warehouse_db, and wiring a live warehouse
   * API call is explicitly step 5, not this step — so for now unitPrice
   * is taken as given on OrderItemInputDto (see its own TODO) and there
   * is NO active-status check on the product. Step 5 must restore both by
   * calling the warehouse's `GET /api/v1/catalogue` (or a per-product
   * lookup) here.
   */
  private buildLineInputs(items: OrderItemInputDto[]): LineInput[] {
    return items.map((item) => {
      const unitPrice = item.unitPrice;
      const lineTotal = round2(unitPrice * item.quantity);
      return { productId: item.productId, quantityOrdered: item.quantity, unitPrice, lineTotal };
    });
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
