/**
 * The full Phase 1 permission catalog from ARCHITECTURE.md §F. Modules
 * built in later phases (products, inventory, orders, fulfilment,
 * warehouse) are declared here now so role/permission assignment doesn't
 * need a schema change later — but no route in this codebase enforces
 * them yet outside users/roles/permissions/audit, since only Phase 1A is
 * implemented.
 */
export interface PermissionDefinition {
  key: string;
  description: string;
  module: string;
}

export const PERMISSION_CATALOG: PermissionDefinition[] = [
  { key: 'catalogue.view', description: 'View product catalogue', module: 'products' },
  { key: 'products.manage', description: 'Create/update/deactivate products', module: 'products' },

  { key: 'customers.create', description: 'Create customers', module: 'customers' },
  { key: 'customers.view', description: 'View customers', module: 'customers' },

  { key: 'orders.create', description: 'Create orders', module: 'orders' },
  { key: 'orders.edit_own_draft', description: 'Edit own draft orders', module: 'orders' },
  { key: 'orders.submit', description: 'Submit orders for approval', module: 'orders' },
  { key: 'orders.approve', description: 'Approve submitted orders', module: 'orders' },
  { key: 'orders.reject', description: 'Reject submitted orders', module: 'orders' },
  { key: 'orders.view_team', description: "View team members' orders", module: 'orders' },
  { key: 'orders.view_own', description: 'View own orders', module: 'orders' },

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

  { key: 'fulfilment.pick', description: 'Pick order items', module: 'fulfilment' },
  { key: 'fulfilment.pack', description: 'Pack orders', module: 'fulfilment' },
  { key: 'fulfilment.dispatch', description: 'Dispatch orders', module: 'fulfilment' },

  { key: 'warehouse.structure.manage', description: 'Manage warehouse/location tree', module: 'warehouses' },

  { key: 'users.manage', description: 'Manage users', module: 'users' },
  { key: 'roles.manage', description: 'Manage roles and role permissions', module: 'roles' },

  { key: 'audit.view', description: 'View audit logs', module: 'audit' },
  { key: 'reports.view', description: 'View reports and the manager dashboard', module: 'reports' },
];

export const ROLE_PERMISSION_MAP: Record<string, string[]> = {
  ADMIN: PERMISSION_CATALOG.map((p) => p.key),
  MANAGER: [
    'catalogue.view',
    'customers.create',
    'customers.view',
    'orders.create',
    'orders.submit',
    'orders.approve',
    'orders.reject',
    'orders.view_team',
    'orders.view_own',
    'inventory.view',
    'inventory.adjust.approve',
    'audit.view',
    'reports.view',
  ],
  WAREHOUSE: [
    'catalogue.view',
    'orders.view_own',
    'inventory.view',
    'inventory.receive',
    'inventory.transfer',
    'inventory.count',
    'inventory.adjust.request',
    'fulfilment.pick',
    'fulfilment.pack',
    'fulfilment.dispatch',
  ],
  CONSULTANT: [
    'catalogue.view',
    'customers.create',
    'customers.view',
    'orders.create',
    'orders.edit_own_draft',
    'orders.submit',
    'orders.view_own',
  ],
};
