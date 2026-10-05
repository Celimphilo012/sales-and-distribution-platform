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
  TrackingMode: values('BULK', 'SERIAL'),
  InventoryUnitSource: values('GENERATED', 'SUPPLIER'),
  InventoryUnitStatus: values('PENDING', 'ON_HAND', 'RESERVED', 'DAMAGED', 'LOST', 'EXPIRED', 'ISSUED'),
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
  SaleCampaignEligibility: values('ALL_CUSTOMERS', 'RESTRICTED'),
  SaleCampaignStatus: values('PENDING_APPROVAL', 'SCHEDULED', 'ACTIVE', 'ENDED', 'REJECTED', 'CANCELLED'),
  SaleDiscountType: values('PERCENT', 'FIXED_AMOUNT', 'FIXED_PRICE'),
};
