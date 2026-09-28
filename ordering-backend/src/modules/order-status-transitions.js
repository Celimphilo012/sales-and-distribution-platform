'use strict';

const { conflict } = require('../core/errors');

/**
 * The full order lifecycle (§I) — one config map, not scattered ifs (rule 7). Every endpoint
 * validates its move against this before writing anything.
 *
 * CANCELLED is reachable from every state up to and including READY_FOR_DISPATCH (cancelling
 * before dispatch releases the reservation). Once DISPATCHED / PARTIALLY_FULFILLED, stock has
 * physically left — no cancel. REJECTED is reachable only from PENDING_APPROVAL.
 */
const ORDER_STATUS_TRANSITIONS = {
  DRAFT: ['SUBMITTED', 'CANCELLED'],
  SUBMITTED: ['PENDING_APPROVAL', 'CANCELLED'],
  PENDING_APPROVAL: ['APPROVED', 'REJECTED', 'CANCELLED'],
  APPROVED: ['STOCK_RESERVED', 'CANCELLED'],
  STOCK_RESERVED: ['PICKING', 'CANCELLED'],
  REJECTED: [],
  CANCELLED: [],
  PICKING: ['PACKED', 'CANCELLED'],
  PACKED: ['READY_FOR_DISPATCH', 'CANCELLED'],
  // /dispatch reaches whichever of these fits: did every line's packed qty meet its ordered qty?
  READY_FOR_DISPATCH: ['DISPATCHED', 'PARTIALLY_FULFILLED', 'CANCELLED'],
  DISPATCHED: ['DELIVERED'],
  PARTIALLY_FULFILLED: ['DELIVERED'],
  DELIVERED: ['COMPLETED'],
  COMPLETED: [],
};

/** Statuses where this order's stock still sits in the warehouse's `reserved` bucket. */
const ORDER_STATUSES_WITH_ACTIVE_RESERVATION = ['STOCK_RESERVED', 'PICKING', 'PACKED', 'READY_FOR_DISPATCH'];

function assertValidOrderTransition(from, to) {
  if (!(ORDER_STATUS_TRANSITIONS[from] ?? []).includes(to)) {
    throw conflict(`Cannot transition order from ${from} to ${to}`);
  }
}

module.exports = { ORDER_STATUS_TRANSITIONS, ORDER_STATUSES_WITH_ACTIVE_RESERVATION, assertValidOrderTransition };
