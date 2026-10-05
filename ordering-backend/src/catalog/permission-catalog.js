'use strict';

/**
 * The permission catalog for the Back-Office / Ordering System (ARCHITECTURE.md §A2). Catalogue,
 * warehouse-structure and inventory permissions live in the warehouse system's own catalog — they
 * are not redeclared here. Roles are data (rule 1): these are only the seeded defaults.
 */
const PERMISSION_CATALOG = [
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

  { key: 'payments.record', description: 'Record payments against orders', module: 'payments' },
  { key: 'payments.void', description: 'Void a recorded payment (kept on record, with a reason)', module: 'payments' },

  { key: 'users.manage', description: 'Manage users', module: 'users' },
  { key: 'roles.manage', description: 'Manage roles and role permissions', module: 'roles' },

  { key: 'sales.view', description: "View the warehouse's sale campaigns", module: 'sales' },
  {
    key: 'sales.eligibility.manage',
    description: 'Manage which customers are eligible for a restricted sale campaign',
    module: 'sales',
  },

  { key: 'audit.view', description: 'View audit logs', module: 'audit' },
  { key: 'reports.view', description: 'View reports and the manager dashboard', module: 'reports' },

  { key: 'finances.view', description: 'View the Finances screen (dashboard, statements, expenses, margin)', module: 'finances' },
  { key: 'finances.expenses.record', description: 'Record an expense', module: 'finances' },
  {
    key: 'finances.expenses.void',
    description: 'Void a recorded expense (kept on record, with a reason)',
    module: 'finances',
  },
  {
    key: 'settings.manage',
    description: 'Configure system settings such as email (SMTP) and SMS (httpSMS) delivery',
    module: 'settings',
  },
];

const ROLE_PERMISSION_MAP = {
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
    'payments.record',
    'payments.void',
    'audit.view',
    'reports.view',
    'sales.view',
    'sales.eligibility.manage',
    'finances.view',
    'finances.expenses.record',
    'finances.expenses.void',
  ],
  WAREHOUSE: ['orders.view_own', 'fulfilment.pick', 'fulfilment.pack', 'fulfilment.dispatch'],
  CONSULTANT: [
    'customers.create',
    'customers.view',
    'orders.create',
    'orders.edit_own_draft',
    'orders.submit',
    'orders.view_own',
  ],
};

module.exports = { PERMISSION_CATALOG, ROLE_PERMISSION_MAP };
