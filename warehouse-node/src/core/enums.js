'use strict';

/**
 * The database's ENUM column values (see db/schema.sql), as frozen JS objects — the single source
 * for route schemas and services. Keep them in step with schema.sql.
 */
const values = (...keys) => Object.freeze(Object.fromEntries(keys.map((k) => [k, k])));

module.exports = {
  UserStatus: values('ACTIVE', 'INACTIVE', 'SUSPENDED'),
  NotifyChannel: values('EMAIL', 'SMS', 'NONE'),
  MfaMethod: values('NONE', 'EMAIL', 'SMS', 'TOTP'),
  OtpChannel: values('EMAIL', 'SMS', 'TOTP'),
  ProductStatus: values('ACTIVE', 'INACTIVE'),
  AttributeDataType: values('TEXT', 'NUMBER'),
  InventoryTransactionType: values(
    'RECEIVE',
    'TRANSFER',
    'ISSUE',
    'SALE',
    'RETURN',
    'ADJUSTMENT',
    'DAMAGED',
    'LOST',
    'STOCK_COUNT',
    'RESERVATION',
    'RELEASE_RESERVATION',
  ),
  AdjustmentBucket: values('ON_HAND', 'RESERVED', 'DAMAGED', 'LOST', 'EXPIRED'),
  AdjustmentDirection: values('INCREASE', 'DECREASE'),
  AdjustmentStatus: values('PENDING', 'APPROVED', 'REJECTED'),
  StockCountStatus: values('OPEN', 'SUBMITTED'),
  StockReservationStatus: values('RESERVED', 'RELEASED', 'ISSUED'),
};
