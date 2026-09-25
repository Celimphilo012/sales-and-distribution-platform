'use strict';

/**
 * The full, fixed set of scopes an API key can hold. `locations:read` lets the
 * back-office relay the leaf-location list to the ordering frontend so a manager
 * reserving an order's stock can pick a real location.
 */
const API_KEY_SCOPES = ['catalogue:read', 'stock:read', 'stock:reserve', 'stock:issue', 'locations:read'];

module.exports = { API_KEY_SCOPES };
