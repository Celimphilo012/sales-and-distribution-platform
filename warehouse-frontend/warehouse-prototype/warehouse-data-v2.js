(function () {
  const OK = 'var(--wh-ok)', WARN = 'var(--wh-warn)', BAD = 'var(--wh-bad)';
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


  // ── v2 additions ──
  const WAREHOUSES = [
    { id: 'JHB-01', name: 'Main Warehouse', code: 'JHB-01', active: true },
    { id: 'CPT-01', name: 'Cape Town DC', code: 'CPT-01', active: true },
    { id: 'DBN-01', name: 'Durban Depot', code: 'DBN-01', active: false },
  ];
  const WORKSTREAMS = [
    { id: 'GRC', name: 'Groceries', code: 'GRC', wh: 'JHB-01', desc: 'Dry goods, oils and canned food', contactName: 'Nomsa Mahlangu', contactEmail: 'groceries@warehouse.example', contactPhone: '+27 11 555 0101', managers: ['Nomsa Mahlangu'], active: true },
    { id: 'HPC', name: 'Household & Personal care', code: 'HPC', wh: 'JHB-01', desc: 'Cleaning, paper and personal care', contactName: 'Lerato Mokoena', contactEmail: 'hpc@warehouse.example', contactPhone: '', managers: ['Lerato Mokoena', 'Thandi Nkosi'], active: true },
    { id: 'BEV', name: 'Beverages', code: 'BEV', wh: 'JHB-01', desc: 'Hot drinks', contactName: '', contactEmail: '', contactPhone: '', managers: [], active: true },
    { id: 'FRZ', name: 'Frozen', code: 'FRZ', wh: 'CPT-01', desc: 'Planned cold-chain range', contactName: '', contactEmail: '', contactPhone: '', managers: [], active: false },
  ];
  const CATEGORIES = [
    ['c-gro', 'Groceries', null, 'GRC'], ['c-sta', 'Staples', 'c-gro', 'GRC'], ['c-oil', 'Oils', 'c-gro', 'GRC'], ['c-can', 'Canned', 'c-gro', 'GRC'],
    ['c-hou', 'Household', null, 'HPC'], ['c-cle', 'Cleaning', 'c-hou', 'HPC'], ['c-pap', 'Paper', 'c-hou', 'HPC'],
    ['c-per', 'Personal care', null, 'HPC'], ['c-soa', 'Soap', 'c-per', 'HPC'],
    ['c-bev', 'Beverages', null, 'BEV'], ['c-hot', 'Hot drinks', 'c-bev', 'BEV'], ['c-juc', 'Juice', 'c-bev', 'BEV', false],
  ].map(([id, name, parent, ws, active]) => ({ id, name, parent, ws, active: active !== false }));
  const catOf = p => CATEGORIES.find(c => c.name === p.sub && c.parent);
  PRODUCTS.forEach(p => { const c = catOf(p); p.catId = c ? c.id : null; p.ws = c ? c.ws : null; });
  const ATTR_TYPES = [
    { id: 'a1', name: 'Pack size', code: 'PACK_SIZE', type: 'TEXT', unit: '', active: true, used: 12 },
    { id: 'a2', name: 'Net weight', code: 'NET_WEIGHT', type: 'NUMBER', unit: 'kg', active: true, used: 7 },
    { id: 'a3', name: 'Volume', code: 'VOLUME', type: 'NUMBER', unit: 'ml', active: true, used: 3 },
    { id: 'a4', name: 'Brand', code: 'BRAND', type: 'TEXT', unit: '', active: true, used: 12 },
    { id: 'a5', name: 'Country of origin', code: 'ORIGIN', type: 'TEXT', unit: '', active: true, used: 5 },
    { id: 'a6', name: 'Shelf life', code: 'SHELF_LIFE', type: 'NUMBER', unit: 'days', active: false, used: 0 },
  ];
  const CAP = l => l.type === 'ZONE' ? 1500 : 400;
  const RECEIPTS = [
    ['GRN-2026-00048', '29 Sep 2026', '10:38', 'P-1001', 120, 'RCV', 'Premier Mills', 'Sipho Dlamini'],
    ['GRN-2026-00047', '28 Sep 2026', '15:12', 'P-1009', 240, 'RCV', 'Lux Brands SA', 'Sipho Dlamini'],
    ['GRN-2026-00046', '28 Sep 2026', '09:40', 'P-1007', 200, 'RCV', 'Koo Foods', 'Thandi Nkosi'],
    ['GRN-2026-00045', '27 Sep 2026', '14:05', 'P-1002', 60, 'A-02-03', 'Sunfoil Distributors', 'Lerato Mokoena'],
    ['GRN-2026-00044', '26 Sep 2026', '11:20', 'P-1005', 96, 'RCV', 'Sunlight Supply', 'Sipho Dlamini'],
    ['GRN-2026-00043', '25 Sep 2026', '08:55', 'P-1003', 80, 'A-03-01', 'Tastic Wholesale', 'Thandi Nkosi'],
    ['GRN-2026-00042', '24 Sep 2026', '13:30', 'P-1012', 48, 'B-01-02', 'Freshpak', 'Sipho Dlamini'],
    ['GRN-2026-00041', '23 Sep 2026', '10:10', 'P-1003', 110, 'RCV', 'Tastic Wholesale', 'Lerato Mokoena'],
    ['GRN-2026-00040', '22 Sep 2026', '16:45', 'P-1008', 180, 'RCV', 'Koo Foods', 'Thandi Nkosi'],
  ].map(([id, date, time, pid, qty, to, supplier, by]) => ({ id, date, time, pid, qty, to, supplier, by }));
  const TRANSFERS = [
    ['TRF-00912', '29 Sep 2026', '10:21', 'P-1007', 48, 'RCV', 'A-02-01', 'Thandi Nkosi'],
    ['TRF-00911', '28 Sep 2026', '16:02', 'P-1005', 36, 'RCV', 'B-01-01', 'Thandi Nkosi'],
    ['TRF-00910', '28 Sep 2026', '11:48', 'P-1009', 120, 'RCV', 'C-04-02', 'Sipho Dlamini'],
    ['TRF-00909', '27 Sep 2026', '09:15', 'P-1001', 40, 'A-01-02', 'DSP', 'Lerato Mokoena'],
    ['TRF-00908', '26 Sep 2026', '14:33', 'P-1003', 30, 'A-03-01', 'DSP', 'Sipho Dlamini'],
    ['TRF-00907', '25 Sep 2026', '10:02', 'P-1008', 90, 'RCV', 'A-02-02', 'Thandi Nkosi'],
  ].map(([id, date, time, pid, qty, from, to, by]) => ({ id, date, time, pid, qty, from, to, by }));
  const PACKING = [
    { ref: 'a1f3c9e2-7b41', label: 'ORD-0142 · Spar Rosebank', reserved: '29 Sep 2026, 09:57', total: 4, lines: [['P-1003', 30, 'A-03-01'], ['P-1001', 12, 'A-01-02'], ['P-1004', 20, 'A-02-02']] },
    { ref: 'b7d0e1a4-22c8', label: 'ORD-0141 · Kwik Mart Soweto', reserved: '28 Sep 2026, 17:20', total: 3, lines: [['P-1005', 24, 'B-01-01'], ['P-1010', 10, 'C-04-02'], ['P-1006', 6, 'A-01-01']] },
    { ref: 'c2e9f5b3-9a10', label: 'ORD-0139 · Corner Café', reserved: '28 Sep 2026, 11:05', total: 2, lines: [['P-1012', 8, 'B-01-02']] },
    { ref: 'd4a8b6c7-11fe', label: null, reserved: '27 Sep 2026, 15:40', total: 2, lines: [['P-1007', 60, 'A-02-01'], ['P-1008', 48, 'A-02-01']] },
  ].map(o => ({ ...o, lines: o.lines.map(([pid, qty, loc]) => ({ pid, qty, loc })) }));
  const REPORTS = [
    { id: 'soh', name: 'Stock on hand', desc: 'Every product balance by location with reserved and available', cat: 'Stock', icon: 'ph-cube' },
    { id: 'low', name: 'Low stock', desc: 'Active products below their minimum level, with shortfall', cat: 'Stock', icon: 'ph-warning' },
    { id: 'val', name: 'Inventory valuation', desc: 'On-hand quantity × cost price per product, with total', cat: 'Finance', icon: 'ph-coins' },
    { id: 'mov', name: 'Stock movements', desc: 'Receipts and transfers in the period, newest first', cat: 'Movements', icon: 'ph-arrows-left-right' },
    { id: 'adj', name: 'Adjustments register', desc: 'Pending, approved and rejected adjustments with reviewers', cat: 'Control', icon: 'ph-sliders-horizontal' },
    { id: 'cnt', name: 'Stock count variances', desc: 'Counts by location with counted progress and net variance', cat: 'Control', icon: 'ph-list-checks' },
    { id: 'util', name: 'Location utilisation', desc: 'Units and fill against capacity for every storage slot', cat: 'Warehouse', icon: 'ph-tree-structure' },
  ];

  window.WH = { TONE, OK, WARN, BAD, fmt, money, GROUPS, PRODUCTS, PBY, LOCS, LBY, LEAVES, path, BD, locStock, units, locQty, PEND, HIST, MOVES, TYPE_TONE, ACTS, COUNTS, USERS, PERMS, ALLP, ROLES, AUDIT, ACTION_TONE, KEYS, WAREHOUSES, WORKSTREAMS, CATEGORIES, ATTR_TYPES, CAP, RECEIPTS, TRANSFERS, PACKING, REPORTS, mix };
})();
