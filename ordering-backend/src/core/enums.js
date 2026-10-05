'use strict';

/** The database's ENUM column values (see db/schema.sql), as frozen JS objects. Keep them in step with it. */
const values = (...keys) => Object.freeze(Object.fromEntries(keys.map((k) => [k, k])));

module.exports = {
  UserStatus: values('ACTIVE', 'INACTIVE', 'SUSPENDED'),
  NotifyChannel: values('EMAIL', 'SMS', 'NONE'),
  MfaMethod: values('NONE', 'EMAIL', 'SMS', 'TOTP'),
  OtpChannel: values('EMAIL', 'SMS', 'TOTP'),
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
  PaymentMethod: values('CASH', 'MOBILE_MONEY', 'BANK_TRANSFER', 'CARD'),
  PaymentRecordStatus: values('RECORDED', 'VOIDED'),
  ExpenseCategory: values('RENT', 'SALARIES', 'UTILITIES', 'TRANSPORT', 'MARKETING', 'SUPPLIES', 'OTHER'),
  ExpenseStatus: values('RECORDED', 'VOIDED'),
};
