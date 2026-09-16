/**
 * Step 1: auth/users/roles. Step 2a: catalogue + warehouse-structure.
 * Step 2b: inventory ledger + operations (receiving/transfers/adjustments/
 * counts) — the final move from /backend. This app's permission catalog is
 * now feature-complete for the warehouse side of the split.
 */
export interface PermissionDefinition {
  key: string;
  description: string;
  module: string;
}

export const PERMISSION_CATALOG: PermissionDefinition[] = [
  { key: 'users.manage', description: 'Manage users', module: 'users' },
  { key: 'roles.manage', description: 'Manage roles and role permissions', module: 'roles' },
  { key: 'audit.view', description: 'View audit logs', module: 'audit' },

  { key: 'catalogue.view', description: 'View product catalogue', module: 'products' },
  { key: 'products.manage', description: 'Create/update/deactivate products and categories', module: 'products' },
  { key: 'warehouse.structure.manage', description: 'Manage warehouse/location tree', module: 'warehouses' },

  { key: 'inventory.view', description: 'View inventory balances', module: 'inventory' },
  { key: 'inventory.receive', description: 'Receive stock', module: 'inventory' },
  { key: 'inventory.transfer', description: 'Transfer stock between locations', module: 'inventory' },
  { key: 'inventory.count', description: 'Perform stock counts', module: 'inventory' },
  {
    key: 'inventory.adjust.request',
    description: 'Request an inventory adjustment (does not move stock by itself)',
    module: 'inventory',
  },
  {
    key: 'inventory.adjust.approve',
    description: 'Approve or reject a requested inventory adjustment — approval is what moves stock',
    module: 'inventory',
  },
];

export const ROLE_PERMISSION_MAP: Record<string, string[]> = {
  ADMIN: PERMISSION_CATALOG.map((p) => p.key),

  // §F: warehouse floor staff — operate the ledger, never approve their
  // own adjustment requests (separation of duties is enforced in
  // StockAdjustmentsService regardless, but this role simply isn't handed
  // the approve permission in the first place).
  WAREHOUSE: [
    'catalogue.view',
    'inventory.view',
    'inventory.receive',
    'inventory.transfer',
    'inventory.count',
    'inventory.adjust.request',
  ],

  // §F: manager-equivalent — reviews/approves adjustments a WAREHOUSE user
  // requested, plus general visibility.
  MANAGER: ['catalogue.view', 'inventory.view', 'inventory.adjust.approve', 'audit.view'],
};
