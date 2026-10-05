'use strict';

/**
 * Actions that must be confirmed with a one-time code (step-up verification), and the wording used
 * in the message that carries the code ("Your code to <description> is 123456"). Config, not
 * scattered ifs (rule 7): to protect another action, add it here and put
 * `requireOtp('<key>')` on its route.
 */
const OTP_ACTIONS = {
  'order.approve': 'approve an order',
  'order.reject': 'reject an order',
  'order.cancel': 'cancel an order',
  'payment.void': 'void a payment',
  'expense.void': 'void an expense',
  'customer.deactivate': 'deactivate a customer',
  'user.deactivate': 'deactivate a user',
  'role.delete': 'delete a role',
  'mfa.disable': 'turn off sign-in verification',
};

module.exports = { OTP_ACTIONS };
