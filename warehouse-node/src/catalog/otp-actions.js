'use strict';

/**
 * Actions that must be confirmed with a one-time code (step-up verification), and the wording used
 * in the message that carries the code ("Your code to <description> is 123456"). Config, not
 * scattered ifs (rule 7): to protect another action, add it here and put
 * `requireOtp('<key>')` on its route.
 */
const OTP_ACTIONS = {
  'stock_adjustment.approve': 'approve a stock adjustment',
  'stock_adjustment.reject': 'reject a stock adjustment',
  'stock_count.submit': 'submit a stock count',
  'product.deactivate': 'deactivate a product',
  'category.deactivate': 'deactivate a category',
  'workstream.deactivate': 'deactivate a workstream',
  'workstream_image.delete': "remove a workstream's image",
  'warehouse.deactivate': 'deactivate a warehouse',
  'location.deactivate': 'deactivate a location',
  'attribute_type.deactivate': 'deactivate an attribute type',
  'product_image.delete': 'delete a product image',
  'user.deactivate': 'deactivate a user',
  'role.delete': 'delete a role',
  'api_key.revoke': 'revoke an API key',
  'mfa.disable': 'turn off sign-in verification',
  'sale_campaign.approve': 'approve a sale campaign',
  'sale_campaign.reject': 'reject a sale campaign',
  'sale_campaign.cancel': 'cancel a sale campaign',
  'sale_campaign.reopen': 'reopen a sale campaign',
};

module.exports = { OTP_ACTIONS };
