import { ConflictException } from '@nestjs/common';
import { OrderStatus } from '@prisma/client';

/**
 * The full order lifecycle (§I). One config map, not scattered `if`s
 * (rule 7): every endpoint validates its move against this before writing
 * anything.
 *
 * Phase 1E built DRAFT through STOCK_RESERVED plus the REJECTED/CANCELLED
 * exceptions; those entries are UNCHANGED. Phase 1F extends the map (not
 * a fork) by widening STOCK_RESERVED's targets to include PICKING, and
 * adding the picking/packing/dispatch states through COMPLETED.
 *
 * CANCELLED is reachable from every state up to and including
 * READY_FOR_DISPATCH — cancelling before dispatch still releases
 * reservations (1E behaviour, extended to the new pre-dispatch states).
 * Once DISPATCHED (or PARTIALLY_FULFILLED), cancel is no longer offered —
 * physical stock has left the building; a return flow (RETURNED) is out
 * of scope for 1F. REJECTED remains reachable only from PENDING_APPROVAL.
 */
export const ORDER_STATUS_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  DRAFT: ['SUBMITTED', 'CANCELLED'],
  SUBMITTED: ['PENDING_APPROVAL', 'CANCELLED'],
  PENDING_APPROVAL: ['APPROVED', 'REJECTED', 'CANCELLED'],
  APPROVED: ['STOCK_RESERVED', 'CANCELLED'],
  STOCK_RESERVED: ['PICKING', 'CANCELLED'],
  REJECTED: [],
  CANCELLED: [],
  PICKING: ['PACKED', 'CANCELLED'],
  PACKED: ['READY_FOR_DISPATCH', 'CANCELLED'],
  // /dispatch picks whichever of these two is actually reached, based on
  // whether every line's packed qty met its ordered qty (OrdersService.dispatch()).
  READY_FOR_DISPATCH: ['DISPATCHED', 'PARTIALLY_FULFILLED', 'CANCELLED'],
  // No CANCELLED from here on: stock has physically left (rule: "After
  // DISPATCHED, cancel is NOT allowed").
  DISPATCHED: ['DELIVERED'],
  PARTIALLY_FULFILLED: ['DELIVERED'],
  DELIVERED: ['COMPLETED'],
  COMPLETED: [],
};

/**
 * Order statuses where stock is still sitting in the `reserved` bucket for
 * this order (reservation happened, dispatch hasn't). Used by
 * OrdersService.cancel() to decide whether cancelling needs to release
 * reservations — the same release logic 1E always had, now also reachable
 * from the pre-dispatch fulfilment states 1F adds (picking/packing don't
 * touch the ledger, so nothing here changes what "reserved" means).
 */
export const ORDER_STATUSES_WITH_ACTIVE_RESERVATION: OrderStatus[] = [
  'STOCK_RESERVED',
  'PICKING',
  'PACKED',
  'READY_FOR_DISPATCH',
];

export function assertValidOrderTransition(from: OrderStatus, to: OrderStatus): void {
  const allowed = ORDER_STATUS_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw new ConflictException(`Cannot transition order from ${from} to ${to}`);
  }
}
