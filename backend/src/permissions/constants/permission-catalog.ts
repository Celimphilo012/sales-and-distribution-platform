/**
 * The Phase 1 permission catalog for the Back-Office / Ordering System
 * (ARCHITECTURE.md §A2). Catalogue/warehouse-structure/inventory
 * permissions (catalogue.view, products.manage, warehouse.structure.manage,
 * inventory.*) moved to the standalone /warehouse app's own permission
 * catalog in step 3 — they are NOT redeclared here, since no route in this
 * app enforces them any more (step 4 removed the modules that did).
 * fulfilment.* stay: /orders still exposes pick/pack/ready/dispatch/deliver/
 * complete, even though the underlying stock effects are stubbed pending
 * step 5.
 */
export interface PermissionDefinition {
  key: string;
  description: string;
  module: string;
}

export const PERMISSION_CATALOG: PermissionDefinition[] = [
  { key: 'customers.create', description: 'Create customers', module: 'customers' },
  { key: 'customers.view', description: 'View customers', module: 'customers' },

  { key: 'orders.create', description: 'Create orders', module: 'orders' },
  { key: 'orders.edit_own_draft', description: 'Edit own draft orders', module: 'orders' },
  { key: 'orders.submit', description: 'Submit orders for approval', module: 'orders' },
  { key: 'orders.approve', description: 'Approve submitted orders', module: 'orders' },
  { key: 'orders.reject', description: 'Reject submitted orders', module: 'orders' },
  { key: 'orders.view_team', description: "View team members' orders", module: 'orders' },
  { key: 'orders.view_own', description: 'View own orders', module: 'orders' },

  { key: 'fulfilment.pick', description: 'Pick order items', module: 'fulfilment' },
  { key: 'fulfilment.pack', description: 'Pack orders', module: 'fulfilment' },
  { key: 'fulfilment.dispatch', description: 'Dispatch orders', module: 'fulfilment' },

  { key: 'users.manage', description: 'Manage users', module: 'users' },
  { key: 'roles.manage', description: 'Manage roles and role permissions', module: 'roles' },

  { key: 'audit.view', description: 'View audit logs', module: 'audit' },
  { key: 'reports.view', description: 'View reports and the manager dashboard', module: 'reports' },
];

export const ROLE_PERMISSION_MAP: Record<string, string[]> = {
  ADMIN: PERMISSION_CATALOG.map((p) => p.key),
  MANAGER: [
    'customers.create',
    'customers.view',
    'orders.create',
    'orders.submit',
    'orders.approve',
    'orders.reject',
    'orders.view_team',
    'orders.view_own',
    'audit.view',
    'reports.view',
  ],
  WAREHOUSE: [
    'orders.view_own',
    'fulfilment.pick',
    'fulfilment.pack',
    'fulfilment.dispatch',
  ],
  CONSULTANT: [
    'customers.create',
    'customers.view',
    'orders.create',
    'orders.edit_own_draft',
    'orders.submit',
    'orders.view_own',
  ],
};
