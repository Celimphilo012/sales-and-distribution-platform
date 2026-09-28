'use strict';

/** The database's ENUM column values (see db/schema.sql), as frozen JS objects. Keep them in step with it. */
const values = (...keys) => Object.freeze(Object.fromEntries(keys.map((k) => [k, k])));

module.exports = {
  UserStatus: values('ACTIVE', 'INACTIVE', 'SUSPENDED'),
  CustomerStatus: values('ACTIVE', 'INACTIVE'),
  OrderStatus: values(
    'DRAFT',
    'SUBMITTED',
    'PENDING_APPROVAL',
    'APPROVED',
    'STOCK_RESERVED',
    'REJECTED',
    'CANCELLED',
    'PICKING',
    'PACKED',
    'READY_FOR_DISPATCH',
    'DISPATCHED',
    'PARTIALLY_FULFILLED',
    'DELIVERED',
    'COMPLETED',
  ),
  PaymentStatus: values('UNPAID', 'PARTIAL', 'PAID'),
};
