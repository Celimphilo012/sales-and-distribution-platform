"use strict";
exports.ROLE_PERMISSION_MAP = exports.PERMISSION_CATALOG = void 0;
exports.PERMISSION_CATALOG = [
    { key: 'users.manage', description: 'Manage users', module: 'users' },
    { key: 'roles.manage', description: 'Manage roles and role permissions', module: 'roles' },
    { key: 'audit.view', description: 'View audit logs', module: 'audit' },
    {
        key: 'settings.manage',
        description: 'Configure system settings such as email (SMTP) and SMS (httpSMS) delivery',
        module: 'settings',
    },
    { key: 'reports.view', description: 'View reports and the summary dashboard', module: 'reports' },
    { key: 'catalogue.view', description: 'View product catalogue', module: 'products' },
    { key: 'products.manage', description: 'Create/update/deactivate products and categories', module: 'products' },
    {
        key: 'workstreams.manage',
        description: 'Create/edit/deactivate workstream records themselves (not their catalogue — see products.manage)',
        module: 'workstreams',
    },
    {
        key: 'workstreams.assign',
        description: 'Assign or unassign the users who can manage a given workstream\'s catalogue',
        module: 'workstreams',
    },
    {
        key: 'warehouse.structure.view',
        description: 'View warehouses and the location tree (list/get/subtree/children)',
        module: 'warehouses',
    },
    {
        key: 'warehouse.structure.manage',
        description: 'Create/edit/move/deactivate warehouses and locations',
        module: 'warehouses',
    },
    {
        key: 'warehouse.access.all',
        description: 'Access every warehouse without being assigned to it',
        module: 'warehouses',
    },
    {
        key: 'warehouse.access.assign',
        description: 'Assign users to the warehouses they may access',
        module: 'warehouses',
    },
    { key: 'inventory.view', description: 'View inventory balances', module: 'inventory' },
    {
        key: 'packing.view',
        description: 'See the items to pack for open orders (within their warehouses and workstreams)',
        module: 'inventory',
    },
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
exports.ROLE_PERMISSION_MAP = {
    ADMIN: exports.PERMISSION_CATALOG.map((p) => p.key),
    // §F: warehouse floor staff — operate the ledger, never approve their
    // own adjustment requests (separation of duties is enforced in
    // StockAdjustmentsService regardless, but this role simply isn't handed
    // the approve permission in the first place).
    WAREHOUSE: [
        'catalogue.view',
        'warehouse.structure.view',
        'inventory.view',
        'inventory.receive',
        'inventory.transfer',
        'inventory.count',
        'inventory.adjust.request',
        'packing.view',
    ],
    // §F: manager-equivalent — reviews/approves adjustments a WAREHOUSE user
    // requested, plus general visibility.
    MANAGER: [
        'catalogue.view',
        'warehouse.structure.view',
        'inventory.view',
        'inventory.adjust.approve',
        'audit.view',
        'reports.view',
        'packing.view',
    ],
    // A seeded convenience default, not a special-cased identity anywhere in
    // code (rule 1: permissions, not roles) — the SAME permissions ADMIN
    // already has for catalogue work, but automatically narrowed to only the
    // workstream(s) this user is assigned to via WorkstreamManagerService's
    // scoping check, which runs off assignment ROWS, not this role name.
    // Assign a user this role, then assign them to a workstream (Workstreams
    // screen → Managers) to put it into effect; the role alone does nothing.
    WORKSTREAM_MANAGER: ['catalogue.view', 'products.manage', 'packing.view'],
};
