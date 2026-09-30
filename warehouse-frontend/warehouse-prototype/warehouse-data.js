(function () {
  const OK = 'oklch(0.80 0.13 155)', WARN = 'oklch(0.83 0.13 80)', BAD = 'oklch(0.74 0.16 25)';
  const mix = (c, p) => `color-mix(in oklab, ${c} ${p}%, transparent)`;
  const TONE = {
    ok: { fg: OK, bg: mix(OK, 15) },
    warn: { fg: WARN, bg: mix(WARN, 15) },
    bad: { fg: BAD, bg: mix(BAD, 16) },
    info: { fg: 'var(--color-accent-300)', bg: 'var(--color-accent-900)' },
    neutral: { fg: 'var(--color-neutral-300)', bg: 'var(--color-neutral-900)' },
  };
  const fmt = n => Number(n).toLocaleString('en-US');
  const money = n => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const GROUPS = [
    { id: 'overview', title: 'Dashboard', short: 'Home', icon: 'ph-gauge', flat: true, items: [{ id: 'dashboard', label: 'Dashboard', icon: 'ph-gauge' }] },
    { id: 'catalogue', title: 'Catalogue', short: 'Catalogue', icon: 'ph-folders', items: [
      { id: 'products', label: 'Products', icon: 'ph-package' },
      { id: 'workstreams', label: 'Workstreams', icon: 'ph-flow-arrow' },
      { id: 'categories', label: 'Categories', icon: 'ph-squares-four' },
      { id: 'attributes', label: 'Attribute Types', icon: 'ph-tag' }] },
    { id: 'warehousing', title: 'Warehousing', short: 'Warehouse', icon: 'ph-warehouse', items: [
      { id: 'warehouses', label: 'Warehouses', icon: 'ph-buildings' },
      { id: 'locations', label: 'Warehouse Structure', icon: 'ph-tree-structure' }] },
    { id: 'stock', title: 'Stock', short: 'Stock', icon: 'ph-stack', items: [
      { id: 'inventory', label: 'Inventory', icon: 'ph-cube' },
      { id: 'receiving', label: 'Stock Receiving', icon: 'ph-box-arrow-down' },
      { id: 'transfers', label: 'Stock Transfers', icon: 'ph-arrows-left-right' },
      { id: 'counts', label: 'Stock Counts', icon: 'ph-list-checks' },
      { id: 'adjustments', label: 'Stock Adjustments', icon: 'ph-sliders-horizontal' },
      { id: 'packing', label: 'Packing', icon: 'ph-package' }] },
    { id: 'usermgmt', title: 'User management', short: 'Users', icon: 'ph-users-three', items: [
      { id: 'users', label: 'Users', icon: 'ph-users' },
      { id: 'roles', label: 'Roles', icon: 'ph-lock-key' }] },
    { id: 'system', title: 'System', short: 'System', icon: 'ph-gear-six', items: [
      { id: 'audit', label: 'Audit Log', icon: 'ph-list-magnifying-glass' },
      { id: 'settings', label: 'Settings', icon: 'ph-sliders' }] },
  ];

  const PRODUCTS = [
    ['P-1001', 'Maize Meal 10kg', 'Groceries', 'Staples', 'bag', 145, 118, 40, 212, 'Active'],
    ['P-1002', 'Sunflower Oil 2L', 'Groceries', 'Oils', 'bottle', 89.99, 71.2, 60, 38, 'Active'],
    ['P-1003', 'Long Grain Rice 5kg', 'Groceries', 'Staples', 'bag', 112.5, 88, 50, 96, 'Active'],
    ['P-1004', 'White Sugar 2kg', 'Groceries', 'Staples', 'pack', 42, 31.5, 80, 64, 'Active'],
    ['P-1005', 'Dish Liquid 750ml', 'Household', 'Cleaning', 'bottle', 27.99, 18.4, 30, 141, 'Active'],
    ['P-1006', 'Laundry Powder 2kg', 'Household', 'Cleaning', 'box', 74.5, 55, 25, 12, 'Active'],
    ['P-1007', 'Tomato Paste 400g', 'Groceries', 'Canned', 'tin', 14.99, 9.8, 100, 418, 'Active'],
    ['P-1008', 'Baked Beans 410g', 'Groceries', 'Canned', 'tin', 16.5, 10.9, 100, 355, 'Active'],
    ['P-1009', 'Bath Soap 175g', 'Personal care', 'Soap', 'bar', 11.25, 6.9, 120, 88, 'Active'],
    ['P-1010', 'Toilet Paper 9-pack', 'Household', 'Paper', 'pack', 64, 47, 40, 22, 'Active'],
    ['P-1011', 'Instant Coffee 200g', 'Beverages', 'Hot drinks', 'jar', 98, null, 20, 57, 'Inactive'],
    ['P-1012', 'Rooibos Tea 80s', 'Beverages', 'Hot drinks', 'box', 46, 33, 30, 73, 'Active'],
  ].map(([sku, name, cat, sub, uom, price, cost, min, stock, status], idx) => ({ id: sku, idx, sku, name, cat, sub, uom, price, cost, min, stock, status }));
  const PBY = Object.fromEntries(PRODUCTS.map(p => [p.id, p]));

  const LOCS = [
    ['RCV', 'Receiving Bay', 'ZONE', null], ['A', 'Aisle A', 'AISLE', null],
    ['A-01', 'Rack 01', 'RACK', 'A'], ['A-01-01', 'Level 01', 'LEVEL', 'A-01'], ['A-01-02', 'Level 02', 'LEVEL', 'A-01'],
    ['A-02', 'Rack 02', 'RACK', 'A'], ['A-02-01', 'Level 01', 'LEVEL', 'A-02'], ['A-02-02', 'Level 02', 'LEVEL', 'A-02'], ['A-02-03', 'Level 03', 'LEVEL', 'A-02'],
    ['A-03', 'Rack 03', 'RACK', 'A'], ['A-03-01', 'Level 01', 'LEVEL', 'A-03'],
    ['B', 'Aisle B', 'AISLE', null], ['B-01', 'Rack 01', 'RACK', 'B'], ['B-01-01', 'Level 01', 'LEVEL', 'B-01'], ['B-01-02', 'Level 02', 'LEVEL', 'B-01'],
    ['C', 'Aisle C', 'AISLE', null], ['C-04', 'Rack 04', 'RACK', 'C'], ['C-04-02', 'Level 02', 'LEVEL', 'C-04'], ['C-04-03', 'Level 03', 'LEVEL', 'C-04', true],
    ['DSP', 'Dispatch', 'ZONE', null],
  ].map(([id, name, type, parent, inactive]) => ({ id, code: id, name, type, parent, inactive: !!inactive }));
  const LBY = Object.fromEntries(LOCS.map(l => [l.id, l]));
  LOCS.forEach(l => { l.children = LOCS.filter(c => c.parent === l.id).map(c => c.id); l.leaf = l.children.length === 0; let d = 0, p = l.parent; while (p) { d++; p = LBY[p].parent; } l.depth = d; });
  const path = id => { const out = []; let c = LBY[id]; while (c) { out.unshift(c.name); c = LBY[c.parent]; } return out; };
  const LEAVES = LOCS.filter(l => l.leaf && !l.inactive);

  const breakdown = p => {
    const L = LEAVES, n = L.length;
    const a = L[(p.idx * 3) % n], b = L[(p.idx * 3 + 4) % n], c = L[(p.idx * 3 + 7) % n];
    const q1 = Math.round(p.stock * 0.6), q2 = Math.round(p.stock * 0.3), q3 = p.stock - q1 - q2;
    return [[a, q1], [b, q2], [c, q3]].filter(x => x[1] > 0).map(([l, q], j) => ({ loc: l, onHand: q, reserved: j === 0 ? Math.round(q * 0.15) : 0 }));
  };
  const BD = Object.fromEntries(PRODUCTS.map(p => [p.id, breakdown(p)]));
  const locStock = lid => PRODUCTS.flatMap(p => BD[p.id].filter(r => r.loc.id === lid).map(r => ({ p, onHand: r.onHand, reserved: r.reserved })));
  const units = id => { const l = LBY[id]; if (l.leaf) return locStock(id).reduce((a, r) => a + r.onHand, 0); return l.children.reduce((a, c) => a + units(c), 0); };
  const locQty = (pid, lid) => (BD[pid].find(r => r.loc.id === lid) || { onHand: 0 }).onHand;

  const PEND = [
    { id: 'ADJ-311', pid: 'P-1002', delta: 6, dir: 'DECREASE', bucket: 'ON_HAND', loc: 'A-02-03', reason: 'Damaged in handling during putaway', by: 'Thandi Nkosi', when: '25 Sep 2026, 14:20', days: 4 },
    { id: 'ADJ-314', pid: 'P-1006', delta: 2, dir: 'DECREASE', bucket: 'ON_HAND', loc: 'B-01-01', reason: 'Count variance, rack B-01', by: 'Sipho Dlamini', when: '27 Sep 2026, 09:02', days: 2 },
    { id: 'ADJ-316', pid: 'P-1009', delta: 24, dir: 'INCREASE', bucket: 'ON_HAND', loc: 'C-04-02', reason: 'Carton found behind pallet', by: 'Lerato Mokoena', when: '28 Sep 2026, 16:45', days: 1 },
    { id: 'ADJ-318', pid: 'P-1001', delta: 1, dir: 'INCREASE', bucket: 'DAMAGED', loc: 'A-01-02', reason: 'Torn bag moved to damaged', by: 'Nomsa Mahlangu', when: '29 Sep 2026, 08:15', days: 0 },
    { id: 'ADJ-319', pid: 'P-1003', delta: 10, dir: 'INCREASE', bucket: 'ON_HAND', loc: 'A-03-01', reason: 'Supplier over-delivery on GRN-2026-00041', by: 'Sipho Dlamini', when: '29 Sep 2026, 09:30', days: 0 },
  ];
  const HIST = [
    { id: 'ADJ-309', pid: 'P-1007', delta: 12, dir: 'DECREASE', bucket: 'ON_HAND', loc: 'A-02-01', status: 'Approved', reviewer: 'Nomsa Mahlangu', note: 'Matches damage report', when: '24 Sep 2026' },
    { id: 'ADJ-305', pid: 'P-1012', delta: 5, dir: 'INCREASE', bucket: 'ON_HAND', loc: 'B-01-02', status: 'Rejected', reviewer: 'Nomsa Mahlangu', note: 'Recount the level first', when: '22 Sep 2026' },
    { id: 'ADJ-301', pid: 'P-1005', delta: 3, dir: 'DECREASE', bucket: 'LOST', loc: 'A-01-01', status: 'Approved', reviewer: 'Pieter van Wyk', note: '—', when: '19 Sep 2026' },
  ];

  const MOVES = [['RECEIVE', 142, 'ok'], ['TRANSFER', 96, 'info'], ['RESERVATION', 81, 'info'], ['RELEASE_RESERVATION', 22, 'info'], ['ADJUSTMENT', 14, 'warn'], ['STOCK_COUNT', 9, 'warn'], ['DAMAGED', 6, 'bad'], ['RETURN', 4, 'ok']];
  const TYPE_TONE = { RECEIVE: 'ok', RETURN: 'ok', DAMAGED: 'bad', LOST: 'bad', ADJUSTMENT: 'warn', STOCK_COUNT: 'warn', TRANSFER: 'info', RESERVATION: 'info', RELEASE_RESERVATION: 'info' };
  const ACTS = [
    { type: 'RECEIVE', pid: 'P-1001', qty: 120, from: null, to: 'RCV', by: 'Sipho Dlamini', when: '10:38' },
    { type: 'TRANSFER', pid: 'P-1007', qty: 48, from: 'RCV', to: 'A-02-01', by: 'Thandi Nkosi', when: '10:21' },
    { type: 'RESERVATION', pid: 'P-1003', qty: 30, from: 'A-03-01', to: null, by: 'Back-office (API key)', when: '09:57' },
    { type: 'ADJUSTMENT', pid: 'P-1012', qty: 5, from: null, to: 'B-01-02', by: 'Nomsa Mahlangu', when: '09:12' },
    { type: 'DAMAGED', pid: 'P-1002', qty: 4, from: 'A-02-03', to: null, by: 'Lerato Mokoena', when: 'Yesterday' },
    { type: 'RECEIVE', pid: 'P-1009', qty: 240, from: null, to: 'RCV', by: 'Sipho Dlamini', when: 'Yesterday' },
    { type: 'TRANSFER', pid: 'P-1005', qty: 36, from: 'RCV', to: 'B-01-01', by: 'Thandi Nkosi', when: 'Yesterday' },
  ];

  const COUNTS = [
    { id: 'SC-0142', loc: 'A-02-03', items: 14, counted: 9, variance: -3, by: 'Sipho Dlamini', started: '29 Sep 2026, 08:12', status: 'In progress' },
    { id: 'SC-0141', loc: 'B-01-01', items: 22, counted: 22, variance: -5, by: 'Thandi Nkosi', started: '28 Sep 2026, 15:40', status: 'Submitted' },
    { id: 'SC-0140', loc: 'A-01-01', items: 8, counted: 3, variance: 0, by: 'Lerato Mokoena', started: '28 Sep 2026, 09:05', status: 'In progress' },
    { id: 'SC-0139', loc: 'C-04-02', items: 17, counted: 17, variance: 2, by: 'Sipho Dlamini', started: '26 Sep 2026, 13:30', status: 'Submitted' },
    { id: 'SC-0138', loc: 'RCV', items: 6, counted: 6, variance: 0, by: 'Thandi Nkosi', started: '24 Sep 2026, 07:55', status: 'Submitted' },
  ];

  const USERS = [
    ['Nomsa Mahlangu', 'nomsa.mahlangu@warehouse.example', ['Warehouse Manager'], ['JHB-01'], 'Authenticator app', 'Active'],
    ['Pieter van Wyk', 'pieter.vanwyk@warehouse.example', ['Admin'], ['JHB-01', 'CPT-01'], 'Authenticator app', 'Active'],
    ['Sipho Dlamini', 'sipho.dlamini@warehouse.example', ['Warehouse Staff'], ['JHB-01'], 'Email code', 'Active'],
    ['Thandi Nkosi', 'thandi.nkosi@warehouse.example', ['Warehouse Staff'], ['JHB-01'], 'Email code', 'Active'],
    ['Lerato Mokoena', 'lerato.mokoena@warehouse.example', ['Warehouse Staff', 'Packing Clerk'], ['JHB-01', 'CPT-01'], 'Authenticator app', 'Active'],
    ['Ayanda Zulu', 'ayanda.zulu@warehouse.example', ['Packing Clerk'], ['JHB-01'], 'Email code', 'Suspended'],
    ['Karen Botha', 'karen.botha@warehouse.example', ['Auditor'], [], 'Email code', 'Inactive'],
  ].map(([name, email, roles, whs, mfa, status]) => ({ name, email, roles, whs, mfa, status, initials: name.split(' ').map(x => x[0]).slice(0, 2).join('') }));

  const PERMS = [
    ['Reports', ['reports.view']],
    ['Catalogue', ['catalogue.view', 'products.manage']],
    ['Warehouse', ['warehouse.structure.manage']],
    ['Inventory', ['inventory.view', 'inventory.receive', 'inventory.transfer', 'inventory.count', 'inventory.adjust.request', 'inventory.adjust.approve']],
    ['Packing', ['packing.view']],
    ['Administration', ['users.manage', 'roles.manage', 'audit.view', 'settings.manage']],
  ];
  const ALLP = PERMS.flatMap(g => g[1]);
  const ROLES = [
    { id: 'admin', name: 'Admin', system: true, desc: 'Full access to every warehouse screen and setting', perms: ALLP },
    { id: 'mgr', name: 'Warehouse Manager', system: true, desc: 'Runs daily operations and approves adjustments', perms: ALLP.filter(k => !['roles.manage', 'settings.manage', 'packing.view'].includes(k)) },
    { id: 'staff', name: 'Warehouse Staff', system: true, desc: 'Receives, moves and counts stock', perms: ['catalogue.view', 'inventory.view', 'inventory.receive', 'inventory.transfer', 'inventory.count', 'inventory.adjust.request'] },
    { id: 'aud', name: 'Auditor', system: false, desc: 'Read-only access to reports and the audit log', perms: ['reports.view', 'inventory.view', 'audit.view'] },
    { id: 'pack', name: 'Packing Clerk', system: false, desc: 'Packs orders for dispatch', perms: ['packing.view', 'inventory.view'] },
  ];

  const AUDIT = [
    ['29 Sep 2026', '10:42', 'Nomsa Mahlangu', false, 'APPROVE', 'stock_adjustments', 'ADJ-309', { status: 'PENDING' }, { status: 'APPROVED', reviewNote: 'Matches damage report' }],
    ['29 Sep 2026', '10:31', 'Back-office ordering', true, 'CREATE', 'reservations', 'RES-1193', null, { productId: 'P-1003', quantity: 30, locationId: 'A-03-01' }],
    ['29 Sep 2026', '10:21', 'Thandi Nkosi', false, 'CREATE', 'inventory_transactions', 'TRX-88412', null, { type: 'TRANSFER', productId: 'P-1007', quantity: 48, from: 'RCV', to: 'A-02-01' }],
    ['29 Sep 2026', '09:48', 'Pieter van Wyk', false, 'UPDATE', 'products', 'P-1011', { status: 'ACTIVE' }, { status: 'INACTIVE' }],
    ['29 Sep 2026', '09:30', 'Sipho Dlamini', false, 'CREATE', 'stock_adjustments', 'ADJ-319', null, { productId: 'P-1003', delta: '10', direction: 'INCREASE' }],
    ['29 Sep 2026', '08:02', 'Nomsa Mahlangu', false, 'LOGIN', 'auth', null, null, null],
    ['28 Sep 2026', '17:15', 'Pieter van Wyk', false, 'UPDATE', 'roles', 'Warehouse Staff', { permissions: 5 }, { permissions: 6 }],
    ['28 Sep 2026', '16:45', 'Lerato Mokoena', false, 'CREATE', 'stock_adjustments', 'ADJ-316', null, { productId: 'P-1009', delta: '24', direction: 'INCREASE' }],
    ['28 Sep 2026', '15:40', 'Thandi Nkosi', false, 'UPDATE', 'stock_counts', 'SC-0141', { status: 'IN_PROGRESS' }, { status: 'SUBMITTED' }],
    ['28 Sep 2026', '11:03', 'Pieter van Wyk', false, 'DELETE', 'api_keys', 'Reporting export', { isActive: true }, { isActive: false }],
  ].map(([date, time, who, api, action, entity, entityId, oldV, newV], i) => ({ i, date, time, who, api, action, entity, entityId, oldV, newV }));
  const ACTION_TONE = { CREATE: 'ok', APPROVE: 'ok', UPDATE: 'info', DELETE: 'bad', REJECT: 'bad', LOGIN: 'neutral' };

  const KEYS = [
    { id: 'k1', name: 'Back-office ordering', active: true, scopes: ['stock.read', 'reservations.write'], created: '12 Aug 2026', by: 'Pieter van Wyk', used: '29 Sep 2026, 10:31' },
    { id: 'k2', name: 'Reporting export', active: false, scopes: ['stock.read'], created: '3 Jun 2026', by: 'Pieter van Wyk', used: '27 Sep 2026, 23:00' },
  ];

  window.WH = { TONE, OK, WARN, BAD, fmt, money, GROUPS, PRODUCTS, PBY, LOCS, LBY, LEAVES, path, BD, locStock, units, locQty, PEND, HIST, MOVES, TYPE_TONE, ACTS, COUNTS, USERS, PERMS, ALLP, ROLES, AUDIT, ACTION_TONE, KEYS };
})();
