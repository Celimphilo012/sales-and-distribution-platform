(function () {
  // ─── Theme ──────────────────────────────────────────────────────────
  const THEMES = {
    dark: {
      vars: { '--color-bg': '#161826', '--color-surface': '#232532', '--color-text': '#e9e9ed', '--color-accent': '#9184d9', '--color-divider': 'color-mix(in srgb, #e9e9ed 16%, transparent)',
        '--shadow-sm': '0 0 0 1px #3f424d', '--shadow-md': '0 0 0 1px #595d6c, 0 6px 18px rgba(0,0,0,0.55)', '--shadow-lg': '0 0 0 1px #9397ab, 0 16px 40px rgba(0,0,0,0.65)',
        '--wh-ok': 'oklch(0.80 0.13 155)', '--wh-warn': 'oklch(0.83 0.13 80)', '--wh-bad': 'oklch(0.74 0.16 25)' },
      neutral: ['#f3f5fe', '#e4e7f5', '#cfd3e5', '#b2b6ca', '#9397ab', '#75798c', '#595d6c', '#3f424d', '#292b31'],
      accent: ['#f5f4ff', '#e7e5fe', '#d2cefd', '#b5abfc', '#968ae0', '#796cbf', '#5d5294', '#423a6a', '#2b2741'], scheme: 'dark' },
    light: {
      vars: { '--color-bg': '#eceef7', '--color-surface': '#f8f9fd', '--color-text': '#1f2127', '--color-accent': '#6456b8', '--color-divider': 'color-mix(in srgb, #1f2127 14%, transparent)',
        '--shadow-sm': '0 0 0 1px #d6d9e7', '--shadow-md': '0 0 0 1px #c9cddd, 0 6px 18px rgba(31,33,39,0.10)', '--shadow-lg': '0 0 0 1px #b9bdd0, 0 16px 40px rgba(31,33,39,0.18)',
        '--wh-ok': 'oklch(0.50 0.13 155)', '--wh-warn': 'oklch(0.56 0.13 65)', '--wh-bad': 'oklch(0.54 0.19 25)' },
      neutral: ['#1f2127', '#292b31', '#3f424d', '#555968', '#6b6f80', '#9397ab', '#b9bdd0', '#d6d9e7', '#e5e8f3'],
      accent: ['#241f3d', '#332b5e', '#4a3f8f', '#5a4eaa', '#6d60c6', '#9184d9', '#b5abfc', '#dcd8fd', '#ebe9fe'], scheme: 'light' },
  };
  function applyTheme(name) {
    const t = THEMES[name] || THEMES.dark;
    [document.documentElement, document.body].filter(Boolean).forEach(el => { const r = el.style;
    Object.entries(t.vars).forEach(([k, v]) => r.setProperty(k, v));
    t.neutral.forEach((c, i) => r.setProperty('--color-neutral-' + (i + 1) * 100, c));
    t.accent.forEach((c, i) => { r.setProperty('--color-accent-' + (i + 1) * 100, c); r.setProperty('--color-accent-2-' + (i + 1) * 100, c); });
    r.setProperty('color-scheme', t.scheme); });
    if (document.body) document.body.style.background = t.vars['--color-bg'];
  }

  // ─── Helpers ────────────────────────────────────────────────────────
  const fmt = n => Number(n || 0).toLocaleString('en-US');
  const money = n => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const byId = list => Object.fromEntries(list.map(x => [x.id, x]));
  const uniq = a => [...new Set(a.filter(x => x != null && x !== ''))];
  const pct = x => Math.max(0, Math.min(100, x * 100)) + '%';
  const sum = (a, f) => a.reduce((t, x) => t + (f(x) || 0), 0);
  const pd = s => new Date(String(s).replace(',', ''));
  const OK = 'var(--wh-ok)', WARN = 'var(--wh-warn)', BAD = 'var(--wh-bad)';
  const TONE = () => window.WH.TONE;
  const tagC = (v, tone) => ({ kind: 'tag', v, fg: TONE()[tone].fg, bg: TONE()[tone].bg });
  const tagO = (v, tone) => ({ v, fg: TONE()[tone].fg, bg: TONE()[tone].bg });
  const act = (icon, label, fn, o = {}) => ({ icon, label, fn, ...o });
  const UOMS = ['bag', 'bar', 'bottle', 'box', 'each', 'jar', 'pack', 'tin'];
  const LOC_TYPES = ['WAREHOUSE', 'FLOOR', 'ROOM', 'ZONE', 'AISLE', 'RACK', 'SHELF', 'CAGE', 'LEVEL', 'BIN', 'PALLET', 'OTHER'];
  const childTypes = t => { const i = LOC_TYPES.indexOf(t); const n = i < 0 ? LOC_TYPES : LOC_TYPES.slice(i + 1); return n.length ? n : LOC_TYPES; };

  // Location index over the (mutable) location list
  function locIndex(locs) {
    const by = Object.fromEntries(locs.map(l => [l.id, { ...l, children: [] }]));
    locs.forEach(l => { if (l.parent && by[l.parent]) by[l.parent].children.push(l.id); });
    const list = [];
    const walk = (id, d) => { const n = by[id]; n.depth = d; n.leaf = n.children.length === 0; list.push(n); n.children.forEach(c => walk(c, d + 1)); };
    locs.filter(l => !l.parent || !by[l.parent]).forEach(l => walk(l.id, 0));
    const path = id => { const o = []; let c = by[id]; while (c) { o.unshift(c.name); c = by[c.parent]; } return o; };
    const unitsMemo = {};
    const units = id => { if (id in unitsMemo) return unitsMemo[id]; const n = by[id]; const v = n.leaf ? (window.WH.LBY[id] ? sum(window.WH.locStock(id), r => r.onHand) : 0) : sum(n.children, c => units(c)); return (unitsMemo[id] = v); };
    const cap = id => { const n = by[id]; return n.leaf ? (n.inactive ? 0 : window.WH.CAP(n)) : sum(n.children, c => cap(c)); };
    const descendants = id => { const o = []; const w = x => by[x].children.forEach(c => { o.push(c); w(c); }); w(id); return o; };
    return { by, list, path, units, cap, descendants };
  }

  // ─── Generic list engine ────────────────────────────────────────────
  const emptyVal = (d, v) => v == null || v === '' || v === false || (Array.isArray(v) && !v.length) || (d.type === 'range' && !v.min && !v.max) || (d.type === 'date' && !v.from && !v.to);
  function passes(d, v, r) {
    if (emptyVal(d, v)) return true;
    const x = d.get(r);
    if (d.type === 'select') return Array.isArray(x) ? x.includes(v) : String(x) === String(v);
    if (d.type === 'multi') return Array.isArray(x) ? x.some(y => v.includes(y)) : v.includes(x);
    if (d.type === 'range') { const n = Number(x); if (v.min !== '' && v.min != null && n < Number(v.min)) return false; if (v.max !== '' && v.max != null && n > Number(v.max)) return false; return true; }
    if (d.type === 'toggle') return !!x;
    if (d.type === 'date') { const t = pd(x); if (v.from && t < new Date(v.from)) return false; if (v.to && t > new Date(v.to + 'T23:59')) return false; return true; }
    return true;
  }
  const chipText = (d, v) => {
    if (d.type === 'select') { const o = (d.options || []).find(o => String(o[0]) === String(v)); return d.label + ': ' + (o ? o[1] : v); }
    if (d.type === 'multi') return d.label + ': ' + v.map(x => ((d.options || []).find(o => o[0] === x) || [x, x])[1]).join(', ');
    if (d.type === 'range') return d.label + ': ' + (v.min || '0') + '–' + (v.max || '∞');
    if (d.type === 'date') return d.label + ': ' + (v.from || '…') + ' → ' + (v.to || '…');
    return d.text || d.label;
  };
  const normAct = a => ({ icon: a.icon, label: a.label, text: a.text || '', hasText: !!a.text, noText: !a.text,
    fn: e => { if (e && e.stopPropagation) e.stopPropagation(); a.fn(); },
    color: a.danger ? BAD : a.primary ? 'var(--color-accent)' : 'var(--color-neutral-400)',
    border: a.text ? (a.danger ? BAD : a.primary ? 'var(--color-accent)' : 'var(--color-divider)') : 'transparent' });
  function cell(c) {
    if (c == null || typeof c !== 'object') c = { v: c == null || c === '' ? '—' : c };
    const k = c.kind || 'text';
    return { isText: k === 'text', isTag: k === 'tag', isTags: k === 'tags', isBar: k === 'bar', isAvatar: k === 'avatar', isActions: k === 'actions', isThumb: k === 'thumb',
      v: c.v == null || c.v === '' ? '—' : c.v, sub: c.sub || '', hasSub: !!c.sub, font: c.mono ? 'ui-monospace, Menlo, monospace' : 'inherit', size: c.mono ? '12px' : '13px',
      color: c.color || 'var(--color-text)', weight: c.weight || 400, fg: c.fg, bg: c.bg, icon: c.icon || 'ph-package', iconColor: c.iconColor || 'var(--color-neutral-500)',
      tags: (c.tags || []).map(t => typeof t === 'string' ? { v: t, fg: 'var(--color-accent-100)', bg: 'var(--color-accent-800)' } : t),
      label: c.label == null ? '' : c.label, labelColor: c.labelColor || 'var(--color-text)', w: c.w || '0%', c: c.c || 'var(--color-accent-500)', marker: c.marker ? 'block' : 'none',
      initials: c.initials || '', actions: (c.actions || []).filter(Boolean).map(normAct) };
  }
  const segOpt = (on, label, click, extra = {}) => ({ label, click, color: on ? 'var(--color-accent-200)' : 'var(--color-neutral-400)', bg: on ? 'var(--color-accent-900)' : 'transparent', ...extra });
  const VIEW_META = { table: ['ph-table', 'Table'], list: ['ph-rows', 'List'], grid: ['ph-squares-four', 'Grid'], tree: ['ph-tree-view', 'Tree'], map: ['ph-map-trifold', 'Map'] };

  function buildList(screen, ctx) {
    const make = DEFS[screen]; if (!make) return null;
    const def = make(ctx);
    const ls = ctx.s.ls[screen] || {};
    const f = ls.f || {};
    const setLs = p => ctx.setLs(screen, p);
    const q = (ls.q || '').trim().toLowerCase();
    const quickV = ls.quick != null ? ls.quick : (def.quick ? def.quick.default || '' : '');
    let rows = def.rows;
    if (q && def.search) rows = rows.filter(r => def.search(r).toLowerCase().includes(q));
    if (def.quick && quickV !== '') rows = rows.filter(r => String(def.quick.get(r)) === String(quickV));
    rows = rows.filter(r => (def.filters || []).every(d => passes(d, f[d.key], r)));
    const sort = ls.sort || def.sort;
    const cols = def.columns;
    if (sort) { const c = cols.find(c => c.key === sort.key); if (c && c.sort) rows = [...rows].sort((a, b) => { const x = c.sort(a), y = c.sort(b); return (x > y ? 1 : x < y ? -1 : 0) * sort.dir; }); }
    const views = def.views || ['table', 'list', 'grid'];
    let view = ls.view || def.defaultView || (ctx.phone && views.includes('list') ? 'list' : views[0]);
    if (!views.includes(view)) view = views[0];
    const display = h => h === 'wide' ? (ctx.desktop ? 'table-cell' : 'none') : h === 'md' ? (ctx.phone ? 'none' : 'table-cell') : 'table-cell';
    const activeDefs = (def.filters || []).filter(d => !emptyVal(d, f[d.key]));
    const sortable = cols.filter(c => c.sort && c.label);
    const filterFields = (def.filters || []).map(d => {
      const v = f[d.key]; const setF = nv => setLs({ f: { ...f, [d.key]: nv } });
      const opts = d.options || [];
      return { label: d.label, isSelect: d.type === 'select', isMulti: d.type === 'multi', isRange: d.type === 'range', isToggle: d.type === 'toggle', isDate: d.type === 'date',
        options: d.type === 'select' ? [{ v: '', l: d.any || 'Any', sel: !v }, ...opts.map(([ov, ol]) => ({ v: ov, l: ol, sel: String(v) === String(ov) }))]
          : d.type === 'multi' ? opts.map(([ov, ol]) => { const on = (v || []).includes(ov); return { l: ol, bg: on ? 'var(--color-accent-900)' : 'transparent', color: on ? 'var(--color-accent-200)' : 'var(--color-neutral-400)', border: on ? 'var(--color-accent)' : 'var(--color-divider)', toggle: () => setF(on ? (v || []).filter(x => x !== ov) : [...(v || []), ov]) }; }) : [],
        onChange: e => setF(e.target.value), min: (v && v.min) || '', max: (v && v.max) || '', onMin: e => setF({ ...(v || {}), min: e.target.value }), onMax: e => setF({ ...(v || {}), max: e.target.value }),
        from: (v && v.from) || '', to: (v && v.to) || '', onFrom: e => setF({ ...(v || {}), from: e.target.value }), onTo: e => setF({ ...(v || {}), to: e.target.value }),
        toggle: () => setF(!v), text: d.text || d.label, box: v ? 'ph-check-square' : 'ph-square', boxC: v ? 'var(--color-accent)' : 'var(--color-neutral-500)', span: d.type === 'multi' && !ctx.phone ? 'span 2' : 'span 1' };
    });
    if (sortable.length) filterFields.push({ label: 'Sort by', isSelect: true, span: 'span 1',
      options: sortable.flatMap(c => [[1, '↑'], [-1, '↓']].map(([dir, a]) => ({ v: c.key + '|' + dir, l: c.label + ' ' + a, sel: sort && sort.key === c.key && sort.dir === dir }))),
      onChange: e => { const [key, dir] = e.target.value.split('|'); setLs({ sort: { key, dir: Number(dir) } }); } });
    const open = r => def.open ? def.open(r) : null;
    const tagN = t => t ? { v: t.v, fg: t.fg, bg: t.bg } : null;
    const statRows = rows;
    return {
      title: def.title, sub: def.sub || '', hasSub: !!def.sub,
      actions: (def.actions || []).map(a => ({ ...a, cls: a.primary ? 'btn btn-primary' : 'btn btn-secondary' })),
      stats: def.stats(statRows).map(x => ({ l: x.l, v: x.v, sub: x.sub || '', c: x.c || 'var(--color-text)', icon: x.icon || '' , hasIcon: !!x.icon })),
      hasQuick: !!def.quick, quick: def.quick ? def.quick.options.map(([v, l]) => segOpt(String(quickV) === String(v), l, () => setLs({ quick: v }))) : [],
      q: ls.q || '', setQ: e => setLs({ q: e.target.value }), searchPh: def.searchPh || 'Search',
      filtersOpen: !!ls.open, toggleFilters: () => setLs({ open: !ls.open }), filterCount: activeDefs.length, hasFilterCount: activeDefs.length > 0,
      filterBtnBorder: ls.open || activeDefs.length ? 'var(--color-accent)' : 'var(--color-divider)', filterBtnColor: ls.open || activeDefs.length ? 'var(--color-accent-200)' : 'var(--color-neutral-300)',
      filterFields, hasFilters: filterFields.length > 0,
      chips: activeDefs.map(d => ({ label: chipText(d, f[d.key]), clear: () => setLs({ f: { ...f, [d.key]: d.type === 'multi' ? [] : d.type === 'range' || d.type === 'date' ? {} : '' } }) })),
      hasChips: activeDefs.length > 0, clearAll: () => setLs({ f: {}, q: '', quick: def.quick ? def.quick.default || '' : '' }),
      views: views.map(v => segOpt(v === view, VIEW_META[v][1], () => setLs({ view: v }), { icon: VIEW_META[v][0] })),
      vTable: view === 'table', vList: view === 'list', vGrid: view === 'grid', vTree: view === 'tree', vMap: view === 'map', view,
      columns: cols.map(c => ({ label: c.label, align: c.align || 'left', display: display(c.hide), width: c.width || 'auto',
        click: c.sort ? () => setLs({ sort: { key: c.key, dir: sort && sort.key === c.key ? -sort.dir : 1 } }) : null, cursor: c.sort ? 'pointer' : 'default',
        arrow: sort && sort.key === c.key ? (sort.dir > 0 ? 'ph-caret-up' : 'ph-caret-down') : '', hasArrow: !!(sort && sort.key === c.key) })),
      rows: rows.map(r => ({ open: open(r), cursor: def.open ? 'pointer' : 'default', cells: cols.map(c => ({ ...cell(c.cell(r)), align: c.align || 'left', display: display(c.hide) })) })),
      listRows: rows.map(r => { const x = def.list(r); const acts = (x.actions || []).filter(Boolean).map(normAct); return { open: open(r), title: x.title, sub: x.sub || '', right: x.right == null ? '' : x.right, rightSub: x.rightSub || '', rightColor: x.rightColor || 'var(--color-text)', icon: x.icon || 'ph-circle', iconColor: x.iconColor || 'var(--color-neutral-500)', tag: tagN(x.tag) || {}, hasTag: !!x.tag, actions: acts, hasActions: acts.length > 0 }; }),
      cards: rows.map(r => { const x = def.card(r); const acts = (x.actions || []).filter(Boolean).map(normAct); return { open: open(r), title: x.title, sub: x.sub || '', icon: x.icon || 'ph-circle', iconColor: x.iconColor || 'var(--color-accent-400)', metrics: (x.metrics || []).map(m => ({ l: m.l, v: m.v, c: m.c || 'var(--color-text)' })), tag: tagN(x.tag) || {}, hasTag: !!x.tag, bar: x.bar || {}, hasBar: !!x.bar, actions: acts, hasActions: acts.length > 0 }; }),
      empty: rows.length === 0, notEmpty: rows.length > 0, emptyTitle: (def.empty || ['Nothing here'])[0], emptyMsg: (def.empty || [])[1] || 'Try adjusting your search or filters.',
      countText: rows.length === def.rows.length ? `${fmt(rows.length)} ${rows.length === 1 ? 'record' : 'records'}` : `${fmt(rows.length)} of ${fmt(def.rows.length)} records match`,
      footNote: def.footNote || '', hasFootNote: !!def.footNote, extra: def.extra || {},
    };
  }

  // ─── Forms ──────────────────────────────────────────────────────────
  const FORMS = {
    product(ctx, p) {
      const { db } = ctx; const cats = byId(db.categories);
      const subs = db.categories.filter(c => c.parent && c.active).map(c => [c.id, (cats[c.parent] ? cats[c.parent].name + ' › ' : '') + c.name]);
      ctx.openForm({ title: p ? 'Edit product' : 'New product', sub: p ? p.sku + ' · stock changes only through receiving, transfers and adjustments' : 'Adds a catalogue item. Stock arrives through receiving — never set here.',
        submit: p ? 'Save changes' : 'Create product',
        fields: [{ key: 'sku', label: 'SKU', required: true, placeholder: 'P-1013', disabled: !!p }, { key: 'name', label: 'Name', required: true, placeholder: 'e.g. Cake Flour 2.5kg' },
          { key: 'catId', label: 'Category', type: 'select', required: true, options: subs, span: 2 },
          { key: 'uom', label: 'Unit of measure', type: 'select', required: true, options: UOMS.map(u => [u, u]) }, { key: 'min', label: 'Min stock level', type: 'number', required: true },
          { key: 'price', label: 'Selling price', type: 'number', required: true }, { key: 'cost', label: 'Cost price', type: 'number', hint: 'Leave empty to exclude from valuation' },
          { key: 'brand', label: 'Brand', hint: 'Attribute · BRAND' }, { key: 'pack', label: 'Pack size', hint: 'Attribute · PACK_SIZE' },
          { key: 'desc', label: 'Description', type: 'textarea', span: 2 }],
        values: p ? { sku: p.sku, name: p.name, catId: p.catId, uom: p.uom, min: String(p.min), price: String(p.price), cost: p.cost == null ? '' : String(p.cost), brand: p.brand || '', pack: p.pack || '', desc: p.desc || '' } : { uom: 'each', catId: subs[0] && subs[0][0], min: '10' },
        onSubmit: v => {
          if (!p && db.products.some(x => x.sku.toLowerCase() === v.sku.trim().toLowerCase())) return { sku: 'That SKU already exists' };
          if (Number(v.price) <= 0) return { price: 'Must be greater than 0' };
          const c = cats[v.catId], par = c && cats[c.parent];
          const rec = { name: v.name.trim(), catId: v.catId, sub: c.name, cat: par ? par.name : c.name, ws: c.ws, uom: v.uom, min: Number(v.min), price: Number(v.price), cost: v.cost === '' ? null : Number(v.cost), brand: v.brand, pack: v.pack, desc: v.desc };
          if (p) ctx.update('products', l => l.map(x => x.id === p.id ? { ...x, ...rec } : x));
          else ctx.update('products', l => [...l, { ...rec, id: v.sku.trim(), sku: v.sku.trim(), idx: l.length, stock: 0, status: 'Active' }]);
          ctx.toast('ok', p ? 'Product updated' : 'Product created', `${v.sku.trim()} · ${rec.name}`, p ? null : { label: 'Receive stock', fn: () => { ctx.setState(st => ({ rcv: { ...st.rcv, pid: v.sku.trim() } })); ctx.sheet('receive'); } });
        } });
    },
    workstream(ctx, w) {
      const { db } = ctx;
      ctx.openForm({ title: w ? 'Edit workstream' : 'New workstream', sub: 'Organises the catalogue: Warehouse → Workstream → Category → Product. Never affects stock.', submit: w ? 'Save changes' : 'Create workstream',
        fields: [{ key: 'name', label: 'Name', required: true }, { key: 'code', label: 'Code', required: true, placeholder: 'GRC' },
          { key: 'wh', label: 'Warehouse', type: 'select', required: true, options: db.warehouses.filter(x => x.active).map(x => [x.id, x.name + ' (' + x.code + ')']), span: 2 },
          { key: 'desc', label: 'Description', type: 'textarea', span: 2 },
          { key: 'managers', label: 'Managers', type: 'multi', options: db.users.filter(u => u.status === 'Active').map(u => [u.name, u.name]), span: 2, hint: 'Scoped managers only see this workstream’s catalogue' },
          { key: 'contactName', label: 'Contact name' }, { key: 'contactEmail', label: 'Contact email' }, { key: 'contactPhone', label: 'Contact phone' },
          { key: 'active', label: 'Status', type: 'seg', options: [['yes', 'Active'], ['no', 'Inactive']] }],
        values: w ? { ...w, active: w.active ? 'yes' : 'no', managers: [...w.managers] } : { wh: 'JHB-01', managers: [], active: 'yes' },
        onSubmit: v => {
          const code = v.code.trim().toUpperCase();
          if (db.workstreams.some(x => x.code === code && (!w || x.id !== w.id))) return { code: 'Code already in use' };
          const rec = { name: v.name.trim(), code, wh: v.wh, desc: v.desc || '', managers: v.managers || [], contactName: v.contactName || '', contactEmail: v.contactEmail || '', contactPhone: v.contactPhone || '', active: v.active === 'yes' };
          ctx.update('workstreams', l => w ? l.map(x => x.id === w.id ? { ...x, ...rec } : x) : [...l, { ...rec, id: code }]);
          ctx.toast('ok', w ? 'Workstream updated' : 'Workstream created', rec.name + ' (' + code + ')');
        } });
    },
    category(ctx, c, parentId) {
      const { db } = ctx; const cats = byId(db.categories);
      ctx.openForm({ title: c ? 'Edit category' : parentId ? 'New sub-category' : 'New category', sub: 'A sub-category always belongs to its parent’s workstream.', submit: c ? 'Save changes' : 'Create category',
        fields: [{ key: 'name', label: 'Name', required: true, span: 2 },
          { key: 'parent', label: 'Parent category', type: 'select', options: [['', '— None (top level)']].concat(db.categories.filter(x => !x.parent && (!c || x.id !== c.id)).map(x => [x.id, x.name])), span: 2 },
          { key: 'ws', label: 'Workstream', type: 'select', required: true, options: db.workstreams.map(x => [x.id, x.name]), hint: 'Ignored for sub-categories — inherited from the parent' },
          { key: 'active', label: 'Status', type: 'seg', options: [['yes', 'Active'], ['no', 'Inactive']] }],
        values: c ? { name: c.name, parent: c.parent || '', ws: c.ws, active: c.active ? 'yes' : 'no' } : { parent: parentId || '', ws: parentId ? cats[parentId].ws : 'GRC', active: 'yes' },
        onSubmit: v => {
          const ws = v.parent ? cats[v.parent].ws : v.ws;
          const rec = { name: v.name.trim(), parent: v.parent || null, ws, active: v.active === 'yes' };
          ctx.update('categories', l => c ? l.map(x => x.id === c.id ? { ...x, ...rec } : x) : [...l, { ...rec, id: 'c-' + Math.random().toString(36).slice(2, 7) }]);
          ctx.toast('ok', c ? 'Category updated' : 'Category created', rec.name + (rec.parent ? ' under ' + cats[rec.parent].name : ''));
        } });
    },
    attr(ctx, a) {
      const { db } = ctx;
      ctx.openForm({ title: a ? 'Edit attribute type' : 'New attribute type', sub: 'New active types appear on the product form automatically. Values are descriptive metadata, not variants.', submit: a ? 'Save changes' : 'Create type',
        fields: [{ key: 'name', label: 'Name', required: true, placeholder: 'Country of origin' }, { key: 'code', label: 'Code', required: true, placeholder: 'ORIGIN' },
          { key: 'type', label: 'Data type', type: 'seg', options: [['TEXT', 'Text'], ['NUMBER', 'Number']] }, { key: 'unit', label: 'Unit', placeholder: 'kg, ml, days…', hint: 'Shown after number values' },
          { key: 'active', label: 'Status', type: 'seg', options: [['yes', 'Active'], ['no', 'Inactive']] }],
        values: a ? { ...a, active: a.active ? 'yes' : 'no' } : { type: 'TEXT', active: 'yes' },
        onSubmit: v => {
          const code = v.code.trim().toUpperCase().replace(/\s+/g, '_');
          if (db.attrs.some(x => x.code === code && (!a || x.id !== a.id))) return { code: 'Code already in use' };
          const rec = { name: v.name.trim(), code, type: v.type, unit: v.unit || '', active: v.active === 'yes' };
          ctx.update('attrs', l => a ? l.map(x => x.id === a.id ? { ...x, ...rec } : x) : [...l, { ...rec, id: 'a' + (l.length + 1), used: 0 }]);
          ctx.toast('ok', a ? 'Attribute type updated' : 'Attribute type created', rec.name + ' · ' + code);
        } });
    },
    warehouse(ctx, w) {
      const { db } = ctx;
      ctx.openForm({ title: w ? 'Edit warehouse' : 'New warehouse', sub: 'Build its structure next, from Warehouse Structure.', submit: w ? 'Save changes' : 'Create warehouse',
        fields: [{ key: 'name', label: 'Name', required: true, span: 2 }, { key: 'code', label: 'Code', required: true, placeholder: 'PTA-01', disabled: !!w },
          { key: 'active', label: 'Status', type: 'seg', options: [['yes', 'Active'], ['no', 'Inactive']] }],
        values: w ? { name: w.name, code: w.code, active: w.active ? 'yes' : 'no' } : { active: 'yes' },
        onSubmit: v => {
          const code = v.code.trim().toUpperCase();
          if (!w && db.warehouses.some(x => x.code === code)) return { code: 'Code already in use' };
          ctx.update('warehouses', l => w ? l.map(x => x.id === w.id ? { ...x, name: v.name.trim(), active: v.active === 'yes' } : x) : [...l, { id: code, code, name: v.name.trim(), active: v.active === 'yes' }]);
          ctx.toast('ok', w ? 'Warehouse updated' : 'Warehouse created', v.name.trim() + ' (' + code + ')', w ? null : { label: 'Build structure', fn: () => ctx.go('locations') });
        } });
    },
    location(ctx, mode, loc) {
      const { db } = ctx; const idx = locIndex(db.locs);
      const isEdit = mode === 'edit', parent = mode === 'child' ? loc : null;
      const types = parent ? childTypes(parent.type) : LOC_TYPES;
      ctx.openForm({ title: isEdit ? 'Edit location' : parent ? 'Add child location' : 'Add root location', sub: parent ? 'Under ' + idx.path(parent.id).join(' › ') : isEdit ? idx.path(loc.id).join(' › ') : 'A top-level area of this warehouse', submit: isEdit ? 'Save changes' : 'Add location',
        fields: [{ key: 'name', label: 'Name', required: true, placeholder: 'Rack 04' }, { key: 'code', label: 'Code', required: true, placeholder: parent ? parent.code + '-04' : 'D', disabled: isEdit },
          { key: 'type', label: 'Type', type: 'select', required: true, options: types.map(t => [t, t]), hint: 'Suggested from the parent’s type — a free label, not a constraint' },
          { key: 'desc', label: 'Description', type: 'textarea', span: 2 }],
        values: isEdit ? { name: loc.name, code: loc.code, type: loc.type, desc: loc.desc || '' } : { type: types[0] },
        onSubmit: v => {
          const code = v.code.trim().toUpperCase();
          if (!isEdit && db.locs.some(l => l.id === code)) return { code: 'Code already in use in this warehouse' };
          if (isEdit) ctx.update('locs', l => l.map(x => x.id === loc.id ? { ...x, name: v.name.trim(), type: v.type, desc: v.desc } : x));
          else ctx.update('locs', l => [...l, { id: code, code, name: v.name.trim(), type: v.type, parent: parent ? parent.id : null, inactive: false, desc: v.desc }]);
          if (!isEdit) ctx.setState({ locSel: code });
          ctx.toast('ok', isEdit ? 'Location updated' : 'Location added', v.name.trim() + ' (' + code + ')');
        } });
    },
    levels(ctx, loc) {
      ctx.openForm({ title: 'Create levels', sub: 'Adds numbered child locations under ' + loc.name + ' (' + loc.code + ').', submit: 'Create levels',
        fields: [{ key: 'count', label: 'How many', type: 'number', required: true }, { key: 'type', label: 'Type', type: 'select', options: childTypes(loc.type).map(t => [t, t]) },
          { key: 'prefix', label: 'Name prefix', required: true }, { key: 'start', label: 'Start at', type: 'number', required: true }],
        values: { count: '4', type: childTypes(loc.type).includes('LEVEL') ? 'LEVEL' : childTypes(loc.type)[0], prefix: 'Level', start: String(ctx.db.locs.filter(l => l.parent === loc.id).length + 1) },
        onSubmit: v => {
          const n = Math.min(24, Math.max(1, parseInt(v.count, 10) || 0)), s0 = parseInt(v.start, 10) || 1;
          const add = Array.from({ length: n }, (_, i) => { const k = String(s0 + i).padStart(2, '0'); return { id: loc.code + '-' + k, code: loc.code + '-' + k, name: v.prefix + ' ' + k, type: v.type, parent: loc.id, inactive: false }; }).filter(x => !ctx.db.locs.some(l => l.id === x.id));
          if (!add.length) return { start: 'Those codes already exist' };
          ctx.update('locs', l => [...l, ...add]);
          ctx.toast('ok', `Created ${add.length} ${v.type.toLowerCase()}s`, add[0].code + (add.length > 1 ? ' → ' + add[add.length - 1].code : ''));
        } });
    },
    move(ctx, loc) {
      const idx = locIndex(ctx.db.locs); const bad = new Set([loc.id, ...idx.descendants(loc.id)]);
      ctx.openForm({ title: 'Move location', sub: 'Moves ' + loc.name + ' (' + loc.code + ') and everything under it. Stock moves with it.', submit: 'Move',
        fields: [{ key: 'parent', label: 'New parent', type: 'select', span: 2, options: [['', '— Top level']].concat(idx.list.filter(l => !bad.has(l.id) && !l.leaf).map(l => [l.id, '  '.repeat(l.depth) + l.name + ' (' + l.code + ')'])) }],
        values: { parent: loc.parent || '' },
        onSubmit: v => { ctx.update('locs', l => l.map(x => x.id === loc.id ? { ...x, parent: v.parent || null } : x)); ctx.toast('ok', 'Location moved', loc.code + ' → ' + (v.parent || 'top level')); } });
    },
    user(ctx, u) {
      const { db } = ctx;
      ctx.openForm({ title: u ? 'Edit user' : 'New user', sub: u ? u.email : 'They get an email to set a password and their sign-in check.', submit: u ? 'Save changes' : 'Create user',
        fields: [{ key: 'name', label: 'Full name', required: true }, { key: 'email', label: 'Email', required: true, disabled: !!u },
          { key: 'roles', label: 'Roles', type: 'multi', required: true, options: db.roles.map(r => [r.name, r.name]), span: 2 },
          { key: 'whs', label: 'Warehouses', type: 'multi', options: db.warehouses.filter(w => w.active).map(w => [w.code, w.name + ' · ' + w.code]), span: 2 },
          { key: 'mfa', label: 'Sign-in check', type: 'select', options: [['Authenticator app', 'Authenticator app'], ['Email code', 'Email code']] },
          { key: 'status', label: 'Status', type: 'seg', options: [['Active', 'Active'], ['Suspended', 'Suspended'], ['Inactive', 'Inactive']] }],
        values: u ? { ...u, roles: [...u.roles], whs: [...u.whs] } : { roles: ['Warehouse Staff'], whs: ['JHB-01'], mfa: 'Email code', status: 'Active' },
        onSubmit: v => {
          if (!/^\S+@\S+\.\S+$/.test(v.email)) return { email: 'Enter a valid email' };
          if (!u && db.users.some(x => x.email === v.email)) return { email: 'A user with this email exists' };
          if (!v.roles.length) return { roles: 'Pick at least one role' };
          const rec = { name: v.name.trim(), roles: v.roles, whs: v.whs || [], mfa: v.mfa, status: v.status, initials: v.name.trim().split(/\s+/).map(x => x[0]).slice(0, 2).join('').toUpperCase() };
          ctx.update('users', l => u ? l.map(x => x.email === u.email ? { ...x, ...rec } : x) : [...l, { ...rec, email: v.email.trim() }]);
          ctx.toast('ok', u ? 'User updated' : 'User created', u ? rec.name : 'Sign-in instructions sent to ' + v.email.trim());
        } });
    },
    role(ctx, r) {
      ctx.openForm({ title: r ? 'Edit role' : 'New role', sub: 'Set permissions on the role’s permission sheet.', submit: r ? 'Save changes' : 'Create role',
        fields: [{ key: 'name', label: 'Name', required: true, span: 2, disabled: r && r.system }, { key: 'desc', label: 'Description', type: 'textarea', span: 2 }],
        values: r ? { name: r.name, desc: r.desc } : {},
        onSubmit: v => {
          if (r) ctx.update('roles', l => l.map(x => x.id === r.id ? { ...x, name: v.name.trim(), desc: v.desc } : x));
          else { const id = 'r' + Math.random().toString(36).slice(2, 6); ctx.update('roles', l => [...l, { id, name: v.name.trim(), desc: v.desc || '', system: false, perms: [] }]); setTimeout(() => ctx.sheet('role', id), 50); }
          ctx.toast('ok', r ? 'Role updated' : 'Role created', r ? v.name : 'Now choose its permissions.');
        } });
    },
    adjustment(ctx) {
      const { db, W } = ctx;
      ctx.openForm({ title: 'Request adjustment', sub: 'A request never moves stock — a different reviewer approves it.', submit: 'Send for approval',
        fields: [{ key: 'pid', label: 'Product', type: 'select', required: true, span: 2, options: db.products.map(p => [p.id, p.sku + ' — ' + p.name]) },
          { key: 'loc', label: 'Location', type: 'select', required: true, span: 2, options: W.LEAVES.map(l => [l.id, l.code + ' — ' + W.path(l.id).join(' › ')]) },
          { key: 'bucket', label: 'Bucket', type: 'seg', span: 2, options: [['ON_HAND', 'On hand'], ['DAMAGED', 'Damaged'], ['LOST', 'Lost'], ['EXPIRED', 'Expired']] },
          { key: 'dir', label: 'Direction', type: 'seg', options: [['INCREASE', 'Increase'], ['DECREASE', 'Decrease']] }, { key: 'qty', label: 'Quantity', type: 'number', required: true },
          { key: 'reason', label: 'Reason', type: 'textarea', required: true, span: 2, placeholder: 'What happened, and how you know' }],
        values: { pid: 'P-1004', loc: 'A-02-02', bucket: 'ON_HAND', dir: 'DECREASE' },
        onSubmit: v => {
          if (!(Number(v.qty) > 0)) return { qty: 'Must be greater than 0' };
          const id = 'ADJ-3' + (20 + db.pending.length);
          ctx.update('pending', l => [...l, { id, pid: v.pid, delta: Number(v.qty), dir: v.dir, bucket: v.bucket, loc: v.loc, reason: v.reason.trim(), by: 'Nomsa Mahlangu', when: 'Just now', days: 0 }]);
          ctx.toast('info', 'Request sent for approval', id + ' · ' + W.PBY[v.pid].name);
        } });
    },
    apiKey(ctx) {
      ctx.openForm({ title: 'New API key', sub: 'The raw key is shown once, right after creation.', submit: 'Create key',
        fields: [{ key: 'name', label: 'Name', required: true, span: 2, placeholder: 'Back-office ordering' }, { key: 'scopes', label: 'Scopes', type: 'multi', required: true, span: 2, options: [['stock.read', 'stock.read'], ['reservations.write', 'reservations.write'], ['products.read', 'products.read']] }],
        values: { scopes: ['stock.read'] },
        onSubmit: v => {
          if (!v.scopes.length) return { scopes: 'Pick at least one scope' };
          ctx.update('keys', l => [{ id: 'k' + Date.now(), name: v.name.trim(), active: true, scopes: v.scopes, created: '29 Sep 2026', by: 'Nomsa Mahlangu', used: 'never' }, ...l]);
          ctx.toast('ok', 'API key created — copy it now', 'whk_live_' + Math.random().toString(36).slice(2, 14) + '…', { label: 'Copy key', fn: () => ctx.toast('info', 'Copied to clipboard', '') }, 12000);
        } });
    },
  };

  // ─── Collection definitions ─────────────────────────────────────────
  const statusTag = active => tagC(active ? 'Active' : 'Inactive', active ? 'ok' : 'neutral');
  const statusTagO = active => tagO(active ? 'Active' : 'Inactive', active ? 'ok' : 'neutral');
  const toggleActive = (ctx, key, rec, name, idKey = 'id') => {
    const flip = () => { ctx.update(key, l => l.map(x => x[idKey] === rec[idKey] ? { ...x, active: !x.active } : x)); ctx.toast('ok', name + (rec.active ? ' deactivated' : ' reactivated'), rec.active ? 'Kept in history — not deleted.' : '', rec.active ? { label: 'Undo', fn: () => ctx.update(key, l => l.map(x => x[idKey] === rec[idKey] ? { ...x, active: true } : x)) } : null); };
    if (!rec.active) return flip();
    ctx.confirm('Deactivate ' + name + '?', 'It is marked inactive and hidden from pickers. It is NOT deleted and stays visible in history.', 'Deactivate', true, flip);
  };
  const statusQuick = { get: r => r.active ? 'yes' : 'no', options: [['', 'All'], ['yes', 'Active'], ['no', 'Inactive']] };

  const DEFS = {
    products(ctx) {
      const { db } = ctx; const cats = byId(db.categories), wsBy = byId(db.workstreams);
      const rows = db.products.map(p => { const c = cats[p.catId], par = c && cats[c.parent]; return { ...p, subName: c ? c.name : p.sub, parentName: par ? par.name : p.cat, wsName: wsBy[p.ws] ? wsBy[p.ws].name : '—', low: p.status === 'Active' && p.stock < p.min, value: p.cost ? p.cost * p.stock : 0 }; });
      const setStatus = (p, st) => { ctx.update('products', l => l.map(x => x.id === p.id ? { ...x, status: st } : x)); ctx.toast('ok', 'Product ' + (st === 'Active' ? 'reactivated' : 'deactivated'), p.name, st === 'Active' ? null : { label: 'Undo', fn: () => ctx.update('products', l => l.map(x => x.id === p.id ? { ...x, status: 'Active' } : x)) }); };
      const deact = p => ctx.confirm('Deactivate product?', `This marks "${p.name}" inactive. It stays visible in historical inventory records — it is not deleted.`, 'Deactivate', true, () => setStatus(p, 'Inactive'));
      const stTag = r => tagC(r.status, r.status === 'Active' ? 'ok' : 'neutral');
      return { title: 'Products', sub: 'Catalogue items across every workstream', searchPh: 'SKU or name',
        actions: [{ label: 'Import', icon: 'ph-upload-simple', fn: () => ctx.toast('info', 'Import opens the CSV import flow', 'Map columns, preview, then import.') }, { label: 'New product', icon: 'ph-plus', primary: true, fn: () => FORMS.product(ctx) }],
        rows, search: r => r.sku + ' ' + r.name,
        stats: rs => [{ l: 'Products', v: rs.length, sub: rs.filter(r => r.status === 'Active').length + ' active' }, { l: 'Below minimum', v: rs.filter(r => r.low).length, sub: 'need reordering', c: rs.some(r => r.low) ? WARN : null },
          { l: 'Units on hand', v: fmt(sum(rs, r => r.stock)), sub: 'all locations' }, { l: 'Stock value', v: money(sum(rs, r => r.value)), sub: 'at cost price' }, { l: 'Avg. price', v: rs.length ? money(sum(rs, r => r.price) / rs.length) : '—', sub: 'selling' }],
        quick: { get: r => r.status, options: [['', 'All'], ['Active', 'Active'], ['Inactive', 'Inactive']] },
        filters: [{ key: 'ws', label: 'Workstream', type: 'select', options: db.workstreams.map(w => [w.id, w.name]), get: r => r.ws },
          { key: 'cat', label: 'Category', type: 'select', options: db.categories.filter(c => !c.parent).map(c => [c.name, c.name]), get: r => r.parentName },
          { key: 'uom', label: 'Unit of measure', type: 'multi', options: uniq(db.products.map(p => p.uom)).map(u => [u, u]), get: r => r.uom },
          { key: 'price', label: 'Selling price', type: 'range', get: r => r.price }, { key: 'stock', label: 'On hand', type: 'range', get: r => r.stock },
          { key: 'low', label: 'Stock level', type: 'toggle', text: 'Below minimum only', get: r => r.low }],
        sort: { key: 'sku', dir: 1 },
        columns: [{ key: 'thumb', label: '', width: '40px', cell: () => ({ kind: 'thumb', icon: 'ph-package' }) },
          { key: 'sku', label: 'SKU', sort: r => r.sku, cell: r => ({ v: r.sku, mono: true, color: 'var(--color-neutral-300)' }) },
          { key: 'name', label: 'Name', sort: r => r.name, cell: r => ({ v: r.name, weight: 500, sub: r.parentName + ' › ' + r.subName }) },
          { key: 'ws', label: 'Workstream', hide: 'wide', sort: r => r.wsName, cell: r => ({ v: r.wsName, color: 'var(--color-neutral-300)' }) },
          { key: 'uom', label: 'UOM', hide: 'wide', cell: r => ({ v: r.uom, color: 'var(--color-neutral-400)' }) },
          { key: 'price', label: 'Price', align: 'right', sort: r => r.price, cell: r => money(r.price) },
          { key: 'stock', label: 'Stock vs min', width: '170px', sort: r => r.stock / r.min, cell: r => ({ kind: 'bar', label: fmt(r.stock), labelColor: r.low ? BAD : null, w: pct(r.stock / (r.min * 2)), c: r.low ? BAD : 'var(--color-accent-500)', marker: true }) },
          { key: 'status', label: 'Status', sort: r => r.status, cell: stTag },
          { key: 'act', label: '', width: '72px', cell: r => ({ kind: 'actions', actions: [act('ph-pencil-simple', 'Edit', () => FORMS.product(ctx, r)), r.status === 'Active' ? act('ph-prohibit', 'Deactivate', () => deact(r), { danger: true }) : act('ph-arrow-counter-clockwise', 'Reactivate', () => setStatus(r, 'Active'))] }) }],
        list: r => ({ icon: 'ph-package', title: r.name, sub: r.sku + ' · ' + r.subName + ' · ' + money(r.price), right: fmt(r.stock) + ' / ' + fmt(r.min), rightSub: r.uom, rightColor: r.low ? BAD : null, tag: stTag(r) }),
        card: r => ({ icon: 'ph-package', iconColor: 'var(--color-neutral-400)', title: r.name, sub: r.sku + ' · ' + r.subName, metrics: [{ l: 'Price', v: money(r.price) }, { l: 'On hand', v: fmt(r.stock) + ' ' + r.uom, c: r.low ? BAD : null }], tag: stTag(r), bar: { w: pct(r.stock / (r.min * 2)), c: r.low ? BAD : 'var(--color-accent-500)' } }),
        open: r => () => ctx.sheet('product', r.id), empty: ['No products found', 'Try adjusting your search or filters.'] };
    },

    workstreams(ctx) {
      const { db } = ctx; const whBy = byId(db.warehouses);
      const rows = db.workstreams.map(w => ({ ...w, whName: whBy[w.wh] ? whBy[w.wh].name : w.wh, nCats: db.categories.filter(c => c.ws === w.id).length, nProds: db.products.filter(p => p.ws === w.id).length, units: sum(db.products.filter(p => p.ws === w.id), p => p.stock) }));
      return { title: 'Workstreams', sub: 'Warehouse → Workstream → Category → Product. Organisational only — never affects stock.', searchPh: 'Name or code',
        actions: [{ label: 'New workstream', icon: 'ph-plus', primary: true, fn: () => FORMS.workstream(ctx) }], rows, search: r => r.name + ' ' + r.code,
        stats: rs => [{ l: 'Workstreams', v: rs.length, sub: rs.filter(r => r.active).length + ' active' }, { l: 'Categories', v: sum(rs, r => r.nCats), sub: 'incl. sub-categories' }, { l: 'Products', v: sum(rs, r => r.nProds) }, { l: 'Units on hand', v: fmt(sum(rs, r => r.units)) }, { l: 'Scoped managers', v: uniq(rs.flatMap(r => r.managers)).length, sub: 'limited to their workstreams' }],
        quick: statusQuick,
        filters: [{ key: 'wh', label: 'Warehouse', type: 'select', options: db.warehouses.map(w => [w.id, w.name]), get: r => r.wh }, { key: 'mgr', label: 'Manager', type: 'select', options: uniq(db.workstreams.flatMap(w => w.managers)).map(m => [m, m]), get: r => r.managers },
          { key: 'prods', label: 'Products', type: 'range', get: r => r.nProds }, { key: 'contact', label: 'Contact', type: 'toggle', text: 'Has contact details', get: r => !!(r.contactName || r.contactEmail) }],
        sort: { key: 'name', dir: 1 },
        columns: [{ key: 'name', label: 'Workstream', sort: r => r.name, cell: r => ({ v: r.name, weight: 500, sub: r.code + ' · ' + (r.desc || 'No description') }) },
          { key: 'wh', label: 'Warehouse', hide: 'md', sort: r => r.wh, cell: r => ({ v: r.wh, mono: true, color: 'var(--color-neutral-300)' }) },
          { key: 'cats', label: 'Categories', align: 'right', sort: r => r.nCats, cell: r => r.nCats }, { key: 'prods', label: 'Products', align: 'right', sort: r => r.nProds, cell: r => r.nProds },
          { key: 'mgr', label: 'Managers', hide: 'wide', cell: r => r.managers.length ? { kind: 'tags', tags: r.managers } : { v: 'Everyone with catalogue access', color: 'var(--color-neutral-500)' } },
          { key: 'contact', label: 'Contact', hide: 'wide', cell: r => r.contactName ? { v: r.contactName, sub: r.contactEmail || r.contactPhone } : { v: '—', color: 'var(--color-neutral-500)' } },
          { key: 'status', label: 'Status', sort: r => r.active, cell: r => statusTag(r.active) },
          { key: 'act', label: '', width: '72px', cell: r => ({ kind: 'actions', actions: [act('ph-pencil-simple', 'Edit', () => FORMS.workstream(ctx, r)), act(r.active ? 'ph-prohibit' : 'ph-arrow-counter-clockwise', r.active ? 'Deactivate' : 'Reactivate', () => toggleActive(ctx, 'workstreams', r, r.name), { danger: r.active })] }) }],
        list: r => ({ icon: 'ph-flow-arrow', iconColor: 'var(--color-accent-400)', title: r.name, sub: r.code + ' · ' + r.whName + ' · ' + (r.managers.join(', ') || 'no scoped managers'), right: r.nProds + ' products', rightSub: r.nCats + ' categories', tag: statusTagO(r.active) }),
        card: r => ({ icon: 'ph-flow-arrow', title: r.name, sub: r.code + ' · ' + r.whName, metrics: [{ l: 'Categories', v: r.nCats }, { l: 'Products', v: r.nProds }, { l: 'Units', v: fmt(r.units) }], tag: statusTagO(r.active) }),
        open: r => () => FORMS.workstream(ctx, r), empty: ['No workstreams', 'Create one to organise the catalogue.'] };
    },

    categories(ctx) {
      const { db } = ctx; const cats = byId(db.categories), wsBy = byId(db.workstreams);
      const prodsOf = c => c.parent ? db.products.filter(p => p.catId === c.id).length : sum(db.categories.filter(x => x.parent === c.id), x => db.products.filter(p => p.catId === x.id).length);
      const ordered = db.categories.filter(c => !c.parent).flatMap(c => [c, ...db.categories.filter(x => x.parent === c.id)]).concat(db.categories.filter(c => c.parent && !cats[c.parent]));
      const rows = ordered.map(c => ({ ...c, level: c.parent ? 'sub' : 'top', parentName: c.parent && cats[c.parent] ? cats[c.parent].name : '', wsName: wsBy[c.ws] ? wsBy[c.ws].name : c.ws, nSubs: db.categories.filter(x => x.parent === c.id).length, nProds: prodsOf(c) }));
      return { title: 'Categories', sub: 'Two levels: category and sub-category. A sub-category inherits its parent’s workstream.', searchPh: 'Category name',
        actions: [{ label: 'New category', icon: 'ph-plus', primary: true, fn: () => FORMS.category(ctx) }], rows, search: r => r.name + ' ' + r.parentName,
        stats: rs => [{ l: 'Categories', v: rs.length, sub: rs.filter(r => r.active).length + ' active' }, { l: 'Top level', v: rs.filter(r => r.level === 'top').length }, { l: 'Sub-categories', v: rs.filter(r => r.level === 'sub').length }, { l: 'Products placed', v: sum(rs.filter(r => r.level === 'sub'), r => r.nProds) }, { l: 'Empty', v: rs.filter(r => r.level === 'sub' && !r.nProds).length, sub: 'sub-categories with no products', c: rs.some(r => r.level === 'sub' && !r.nProds) ? WARN : null }],
        quick: { get: r => r.level, options: [['', 'All'], ['top', 'Top level'], ['sub', 'Sub-categories']] },
        filters: [{ key: 'ws', label: 'Workstream', type: 'select', options: db.workstreams.map(w => [w.id, w.name]), get: r => r.ws }, { key: 'parent', label: 'Parent', type: 'select', options: db.categories.filter(c => !c.parent).map(c => [c.id, c.name]), get: r => r.parent },
          { key: 'st', label: 'Status', type: 'select', options: [['yes', 'Active'], ['no', 'Inactive']], get: r => r.active ? 'yes' : 'no' }, { key: 'prods', label: 'Products', type: 'range', get: r => r.nProds }],
        columns: [{ key: 'name', label: 'Category', cell: r => ({ v: (r.level === 'sub' ? '↳ ' : '') + r.name, weight: r.level === 'top' ? 500 : 400, sub: r.level === 'sub' ? 'in ' + r.parentName : r.nSubs + ' sub-categories' }) },
          { key: 'ws', label: 'Workstream', hide: 'md', sort: r => r.wsName, cell: r => ({ v: r.wsName, color: 'var(--color-neutral-300)' }) },
          { key: 'level', label: 'Level', hide: 'wide', cell: r => tagC(r.level === 'top' ? 'Category' : 'Sub-category', r.level === 'top' ? 'info' : 'neutral') },
          { key: 'prods', label: 'Products', align: 'right', sort: r => r.nProds, cell: r => r.nProds },
          { key: 'status', label: 'Status', cell: r => statusTag(r.active) },
          { key: 'act', label: '', width: '100px', cell: r => ({ kind: 'actions', actions: [r.level === 'top' ? act('ph-plus', 'Add sub-category', () => FORMS.category(ctx, null, r.id)) : null, act('ph-pencil-simple', 'Edit', () => FORMS.category(ctx, r)), act(r.active ? 'ph-prohibit' : 'ph-arrow-counter-clockwise', r.active ? 'Deactivate' : 'Reactivate', () => toggleActive(ctx, 'categories', r, r.name), { danger: r.active })] }) }],
        list: r => ({ icon: r.level === 'top' ? 'ph-folder-simple' : 'ph-tag-simple', iconColor: r.level === 'top' ? 'var(--color-accent-400)' : 'var(--color-neutral-500)', title: (r.level === 'sub' ? r.parentName + ' › ' : '') + r.name, sub: r.wsName, right: r.nProds + ' products', tag: statusTagO(r.active) }),
        card: r => ({ icon: r.level === 'top' ? 'ph-folder-simple' : 'ph-tag-simple', title: r.name, sub: (r.level === 'sub' ? 'in ' + r.parentName + ' · ' : '') + r.wsName, metrics: [{ l: 'Products', v: r.nProds }, { l: r.level === 'top' ? 'Sub-categories' : 'Level', v: r.level === 'top' ? r.nSubs : 'Sub' }], tag: statusTagO(r.active) }),
        open: r => () => FORMS.category(ctx, r), empty: ['No categories', 'Adjust filters or add a category.'] };
    },

    attributes(ctx) {
      const { db } = ctx; const rows = db.attrs;
      return { title: 'Attribute Types', sub: 'The admin-managed catalogue behind product attributes. Values are stored as text; Number types validate input.', searchPh: 'Name or code',
        actions: [{ label: 'New attribute type', icon: 'ph-plus', primary: true, fn: () => FORMS.attr(ctx) }], rows, search: r => r.name + ' ' + r.code,
        stats: rs => [{ l: 'Types', v: rs.length, sub: rs.filter(r => r.active).length + ' active' }, { l: 'Text', v: rs.filter(r => r.type === 'TEXT').length }, { l: 'Number', v: rs.filter(r => r.type === 'NUMBER').length, sub: rs.filter(r => r.unit).length + ' with units' }, { l: 'Values in use', v: sum(rs, r => r.used), sub: 'across products' }, { l: 'Unused', v: rs.filter(r => !r.used).length, c: rs.some(r => !r.used) ? WARN : null }],
        quick: { get: r => r.type, options: [['', 'All'], ['TEXT', 'Text'], ['NUMBER', 'Number']] },
        filters: [{ key: 'st', label: 'Status', type: 'select', options: [['yes', 'Active'], ['no', 'Inactive']], get: r => r.active ? 'yes' : 'no' }, { key: 'unit', label: 'Unit', type: 'toggle', text: 'Has a unit', get: r => !!r.unit }, { key: 'used', label: 'Products using', type: 'range', get: r => r.used }],
        sort: { key: 'name', dir: 1 },
        columns: [{ key: 'name', label: 'Name', sort: r => r.name, cell: r => ({ v: r.name, weight: 500 }) }, { key: 'code', label: 'Code', sort: r => r.code, cell: r => ({ v: r.code, mono: true, color: 'var(--color-neutral-300)' }) },
          { key: 'type', label: 'Data type', sort: r => r.type, cell: r => tagC(r.type === 'NUMBER' ? 'Number' : 'Text', r.type === 'NUMBER' ? 'info' : 'neutral') },
          { key: 'unit', label: 'Unit', hide: 'md', cell: r => r.unit || { v: '—', color: 'var(--color-neutral-500)' } }, { key: 'used', label: 'Products', align: 'right', sort: r => r.used, cell: r => r.used },
          { key: 'status', label: 'Status', cell: r => statusTag(r.active) },
          { key: 'act', label: '', width: '72px', cell: r => ({ kind: 'actions', actions: [act('ph-pencil-simple', 'Edit', () => FORMS.attr(ctx, r)), act(r.active ? 'ph-prohibit' : 'ph-arrow-counter-clockwise', r.active ? 'Deactivate' : 'Reactivate', () => toggleActive(ctx, 'attrs', r, r.name), { danger: r.active })] }) }],
        list: r => ({ icon: r.type === 'NUMBER' ? 'ph-hash' : 'ph-text-aa', iconColor: 'var(--color-accent-400)', title: r.name, sub: r.code + (r.unit ? ' · ' + r.unit : ''), right: r.used + ' products', tag: statusTagO(r.active) }),
        card: r => ({ icon: r.type === 'NUMBER' ? 'ph-hash' : 'ph-text-aa', title: r.name, sub: r.code, metrics: [{ l: 'Type', v: r.type === 'NUMBER' ? 'Number' : 'Text' }, { l: 'Unit', v: r.unit || '—' }, { l: 'Products', v: r.used }], tag: statusTagO(r.active) }),
        open: r => () => FORMS.attr(ctx, r), empty: ['No attribute types', 'Adjust filters or add a type.'] };
    },

    warehouses(ctx) {
      const { db } = ctx; const idx = locIndex(db.locs);
      const roots = idx.list.filter(l => l.depth === 0);
      const rows = db.warehouses.map(w => { const main = w.id === 'JHB-01'; const units = main ? sum(roots, r => idx.units(r.id)) : 0, cap = main ? sum(roots, r => idx.cap(r.id)) : 0;
        return { ...w, nLocs: main ? idx.list.length : 0, nSlots: main ? idx.list.filter(l => l.leaf).length : 0, nWs: db.workstreams.filter(x => x.wh === w.id).length, units, cap, util: cap ? units / cap : 0 }; });
      return { title: 'Warehouses', sub: 'Each warehouse owns its location tree and workstreams.', searchPh: 'Name or code',
        actions: [{ label: 'New warehouse', icon: 'ph-plus', primary: true, fn: () => FORMS.warehouse(ctx) }], rows, search: r => r.name + ' ' + r.code,
        stats: rs => { const cap = sum(rs, r => r.cap), u = sum(rs, r => r.units); return [{ l: 'Warehouses', v: rs.length, sub: rs.filter(r => r.active).length + ' active' }, { l: 'Locations', v: fmt(sum(rs, r => r.nLocs)), sub: fmt(sum(rs, r => r.nSlots)) + ' storage slots' }, { l: 'Units on hand', v: fmt(u) }, { l: 'Utilisation', v: cap ? Math.round(u / cap * 100) + '%' : '—', sub: 'of slot capacity' }, { l: 'Not structured', v: rs.filter(r => !r.nLocs).length, sub: 'no locations yet', c: rs.some(r => !r.nLocs && r.active) ? WARN : null }]; },
        quick: statusQuick,
        filters: [{ key: 'struct', label: 'Structure', type: 'toggle', text: 'Has locations', get: r => r.nLocs > 0 }, { key: 'util', label: 'Utilisation %', type: 'range', get: r => Math.round(r.util * 100) }],
        sort: { key: 'name', dir: 1 },
        columns: [{ key: 'name', label: 'Warehouse', sort: r => r.name, cell: r => ({ v: r.name, weight: 500, sub: r.code }) },
          { key: 'ws', label: 'Workstreams', align: 'right', hide: 'md', sort: r => r.nWs, cell: r => r.nWs }, { key: 'locs', label: 'Locations', align: 'right', sort: r => r.nLocs, cell: r => r.nLocs ? fmt(r.nLocs) : { v: 'None yet', color: 'var(--color-neutral-500)' } },
          { key: 'units', label: 'Units', align: 'right', hide: 'md', sort: r => r.units, cell: r => fmt(r.units) },
          { key: 'util', label: 'Utilisation', width: '170px', sort: r => r.util, cell: r => r.cap ? { kind: 'bar', label: Math.round(r.util * 100) + '%', w: pct(r.util), c: r.util > 0.9 ? WARN : 'var(--color-accent-500)' } : { v: '—', color: 'var(--color-neutral-500)' } },
          { key: 'status', label: 'Status', cell: r => statusTag(r.active) },
          { key: 'act', label: '', width: '100px', cell: r => ({ kind: 'actions', actions: [act('ph-tree-structure', 'Open structure', () => ctx.go('locations')), act('ph-pencil-simple', 'Edit', () => FORMS.warehouse(ctx, r)), act(r.active ? 'ph-prohibit' : 'ph-arrow-counter-clockwise', r.active ? 'Deactivate' : 'Reactivate', () => toggleActive(ctx, 'warehouses', r, r.name), { danger: r.active })] }) }],
        list: r => ({ icon: 'ph-buildings', iconColor: 'var(--color-accent-400)', title: r.name, sub: r.code + ' · ' + r.nLocs + ' locations · ' + r.nWs + ' workstreams', right: r.cap ? Math.round(r.util * 100) + '%' : '—', rightSub: 'utilised', tag: statusTagO(r.active) }),
        card: r => ({ icon: 'ph-buildings', title: r.name, sub: r.code, metrics: [{ l: 'Locations', v: fmt(r.nLocs) }, { l: 'Units', v: fmt(r.units) }, { l: 'Utilised', v: r.cap ? Math.round(r.util * 100) + '%' : '—' }], tag: statusTagO(r.active), bar: r.cap ? { w: pct(r.util), c: 'var(--color-accent-500)' } : null }),
        open: r => () => ctx.go('locations'), empty: ['No warehouses', 'Adjust filters or add one.'] };
    },

    locations(ctx) {
      const { db, s } = ctx; const idx = locIndex(db.locs);
      const rows = idx.list.filter(l => s.showInactive || !l.inactive).map(l => { const u = idx.units(l.id), c = idx.cap(l.id); return { ...l, path: idx.path(l.id).join(' › '), parentCode: l.parent || '', aisle: idx.path(l.id)[0], units: u, cap: c, util: c ? u / c : 0, nKids: l.children.length }; });
      const leafRows = rs => rs.filter(r => r.leaf);
      return { title: 'Warehouse Structure', sub: 'Main Warehouse (JHB-01) · any depth; types are free labels', searchPh: 'Name or code', views: ['map', 'tree', 'table', 'list', 'grid'],
        actions: [{ label: 'Add location', icon: 'ph-plus', primary: true, fn: () => FORMS.location(ctx, 'root') }], rows, search: r => r.name + ' ' + r.code,
        stats: rs => { const lr = leafRows(rs), cap = sum(lr, r => r.cap), u = sum(lr, r => r.units); return [{ l: 'Locations', v: rs.length, sub: rs.filter(r => r.inactive).length + ' inactive' }, { l: 'Storage slots', v: lr.length, sub: 'leaf locations' }, { l: 'Units stored', v: fmt(u) }, { l: 'Utilisation', v: cap ? Math.round(u / cap * 100) + '%' : '—', sub: 'of ' + fmt(cap) + ' capacity' }, { l: 'Empty slots', v: lr.filter(r => !r.units && !r.inactive).length, c: 'var(--color-accent-300)', sub: 'ready for putaway' }, { l: 'Near full', v: lr.filter(r => r.util > 0.9).length, sub: 'over 90%', c: lr.some(r => r.util > 0.9) ? WARN : null }]; },
        filters: [{ key: 'type', label: 'Type', type: 'multi', options: uniq(db.locs.map(l => l.type)).map(t => [t, t]), get: r => r.type }, { key: 'aisle', label: 'Top-level area', type: 'select', options: idx.list.filter(l => l.depth === 0).map(l => [l.name, l.name]), get: r => r.aisle },
          { key: 'util', label: 'Utilisation %', type: 'range', get: r => Math.round(r.util * 100) }, { key: 'leaf', label: 'Slots', type: 'toggle', text: 'Storage slots only', get: r => r.leaf }],
        columns: [{ key: 'name', label: 'Location', cell: r => ({ v: '\u00a0'.repeat(r.depth * 3) + r.name, weight: r.leaf ? 400 : 500, sub: '\u00a0'.repeat(r.depth * 3) + r.code }) },
          { key: 'type', label: 'Type', sort: r => r.type, cell: r => tagC(r.type, 'neutral') }, { key: 'path', label: 'Path', hide: 'wide', cell: r => ({ v: r.path, color: 'var(--color-neutral-400)' }) },
          { key: 'units', label: 'Units', align: 'right', sort: r => r.units, cell: r => fmt(r.units) },
          { key: 'util', label: 'Fill', width: '150px', sort: r => r.util, hide: 'md', cell: r => r.cap ? { kind: 'bar', label: Math.round(r.util * 100) + '%', w: pct(r.util), c: r.util > 0.9 ? WARN : 'var(--color-accent-500)' } : '—' },
          { key: 'status', label: 'Status', cell: r => tagC(r.inactive ? 'Inactive' : 'Active', r.inactive ? 'neutral' : 'ok') },
          { key: 'act', label: '', width: '100px', cell: r => ({ kind: 'actions', actions: [act('ph-plus', 'Add child', () => FORMS.location(ctx, 'child', r)), act('ph-pencil-simple', 'Edit', () => FORMS.location(ctx, 'edit', r)), act('ph-arrows-out-cardinal', 'Move', () => FORMS.move(ctx, r))] }) }],
        list: r => ({ icon: r.leaf ? 'ph-cube' : 'ph-folder-simple', iconColor: r.leaf ? 'var(--color-neutral-500)' : 'var(--color-accent-400)', title: r.name + ' · ' + r.code, sub: r.path, right: fmt(r.units), rightSub: r.cap ? Math.round(r.util * 100) + '% full' : r.type, tag: r.inactive ? tagO('Inactive', 'neutral') : null }),
        card: r => ({ icon: r.leaf ? 'ph-cube' : 'ph-folder-simple', title: r.name, sub: r.code + ' · ' + r.type, metrics: [{ l: 'Units', v: fmt(r.units) }, { l: r.leaf ? 'Capacity' : 'Children', v: r.leaf ? fmt(r.cap) : r.nKids }], tag: r.inactive ? tagO('Inactive', 'neutral') : null, bar: r.cap ? { w: pct(r.util), c: r.util > 0.9 ? WARN : 'var(--color-accent-500)' } : null }),
        open: r => () => ctx.setState({ locSel: r.id }), empty: ['No locations match', 'Adjust filters, or add a root location.'], idx };
    },

    inventory(ctx) {
      const { db, W } = ctx; const wsBy = byId(db.workstreams);
      const rows = db.products.flatMap(p => (W.BD[p.id] || []).map(b => ({ id: p.id + '@' + b.loc.id, p, pid: p.id, loc: b.loc.id, path: W.path(b.loc.id), aisle: W.path(b.loc.id)[0], onHand: b.onHand, reserved: b.reserved, avail: b.onHand - b.reserved, ws: p.ws, low: p.stock < p.min })));
      return { title: 'Inventory', sub: 'Read-only balances. Filter by product for “where is it?”, or by location for “what’s here?”.', searchPh: 'Product, SKU or location code',
        actions: [{ label: 'Transfer', icon: 'ph-arrows-left-right', fn: () => ctx.sheet('transfer') }, { label: 'Receive', icon: 'ph-box-arrow-down', primary: true, fn: () => ctx.sheet('receive') }],
        rows, search: r => r.p.name + ' ' + r.p.sku + ' ' + r.loc,
        stats: rs => [{ l: 'On hand', v: fmt(sum(rs, r => r.onHand)), sub: 'units in ' + uniq(rs.map(r => r.loc)).length + ' locations' }, { l: 'Reserved', v: fmt(sum(rs, r => r.reserved)), sub: 'held for orders', c: WARN }, { l: 'Available', v: fmt(sum(rs, r => r.avail)), sub: 'can be picked', c: 'var(--color-accent-300)' }, { l: 'Products', v: uniq(rs.map(r => r.pid)).length, sub: uniq(rs.filter(r => r.low).map(r => r.pid)).length + ' below minimum' }, { l: 'Balances', v: rs.length, sub: 'product × location' }],
        quick: { get: r => r.reserved > 0 ? 'res' : 'free', options: [['', 'All balances'], ['res', 'With reservations'], ['free', 'Unreserved']] },
        filters: [{ key: 'pid', label: 'Product — where is it?', type: 'select', options: db.products.map(p => [p.id, p.sku + ' — ' + p.name]), get: r => r.pid },
          { key: 'loc', label: 'Location — what’s here?', type: 'select', options: W.LEAVES.map(l => [l.id, l.code + ' — ' + W.path(l.id).join(' › ')]), get: r => r.loc },
          { key: 'aisle', label: 'Area', type: 'select', options: uniq(W.LEAVES.map(l => W.path(l.id)[0])).map(a => [a, a]), get: r => r.aisle }, { key: 'ws', label: 'Workstream', type: 'select', options: db.workstreams.map(w => [w.id, w.name]), get: r => r.ws },
          { key: 'onHand', label: 'On hand', type: 'range', get: r => r.onHand }, { key: 'low', label: 'Stock level', type: 'toggle', text: 'Products below minimum', get: r => r.low }],
        sort: { key: 'product', dir: 1 },
        columns: [{ key: 'product', label: 'Product', sort: r => r.p.name, cell: r => ({ v: r.p.name, weight: 500, sub: r.p.sku }) },
          { key: 'loc', label: 'Location', sort: r => r.loc, cell: r => ({ v: r.path[r.path.length - 1] + ' · ' + r.loc, sub: r.path.slice(0, -1).join(' › ') }) },
          { key: 'onHand', label: 'On hand', align: 'right', sort: r => r.onHand, cell: r => fmt(r.onHand) }, { key: 'res', label: 'Reserved', align: 'right', hide: 'md', sort: r => r.reserved, cell: r => ({ v: fmt(r.reserved), color: r.reserved ? WARN : 'var(--color-neutral-500)' }) },
          { key: 'avail', label: 'Available', align: 'right', sort: r => r.avail, cell: r => ({ v: fmt(r.avail), color: 'var(--color-accent-300)', weight: 500 }) },
          { key: 'share', label: 'Reserved share', width: '130px', hide: 'wide', cell: r => ({ kind: 'bar', label: '', w: pct(r.reserved / Math.max(1, r.onHand)), c: WARN }) },
          { key: 'act', label: '', width: '72px', cell: r => ({ kind: 'actions', actions: [act('ph-arrows-left-right', 'Transfer from here', () => { ctx.setState(st => ({ trf: { ...st.trf, pid: r.pid, from: r.loc } })); ctx.sheet('transfer'); }), act('ph-sliders-horizontal', 'Request adjustment', () => FORMS.adjustment(ctx))] }) }],
        list: r => ({ icon: 'ph-cube', title: r.p.name, sub: r.loc + ' · ' + r.path.slice(0, -1).join(' › '), right: fmt(r.avail) + ' avail.', rightSub: fmt(r.onHand) + ' on hand · ' + fmt(r.reserved) + ' res.', rightColor: 'var(--color-accent-300)' }),
        card: r => ({ icon: 'ph-cube', title: r.p.name, sub: r.loc + ' · ' + r.p.sku, metrics: [{ l: 'On hand', v: fmt(r.onHand) }, { l: 'Reserved', v: fmt(r.reserved), c: r.reserved ? WARN : null }, { l: 'Available', v: fmt(r.avail), c: 'var(--color-accent-300)' }], bar: { w: pct(r.reserved / Math.max(1, r.onHand)), c: WARN } }),
        open: r => () => ctx.sheet('product', r.pid), empty: ['No balances match', 'This product or location holds no stock.'] };
    },

    receiving(ctx) {
      const { db, W } = ctx;
      const rows = db.receipts.map(r => ({ ...r, p: db.products.find(p => p.id === r.pid) || W.PBY[r.pid] }));
      return { title: 'Stock Receiving', sub: 'Each receipt is a RECEIVE transaction that increases on-hand at its destination.', searchPh: 'GRN, product or supplier',
        actions: [{ label: 'Receive stock', icon: 'ph-box-arrow-down', primary: true, fn: () => ctx.sheet('receive') }], rows, search: r => r.id + ' ' + r.p.name + ' ' + r.supplier,
        stats: rs => [{ l: 'Receipts', v: rs.length, sub: rs.filter(r => r.date === '29 Sep 2026').length + ' today' }, { l: 'Units received', v: fmt(sum(rs, r => r.qty)) }, { l: 'Suppliers', v: uniq(rs.map(r => r.supplier)).length }, { l: 'Products', v: uniq(rs.map(r => r.pid)).length }, { l: 'Into receiving bay', v: rs.filter(r => r.to === 'RCV').length, sub: 'awaiting putaway', c: 'var(--color-accent-300)' }],
        filters: [{ key: 'sup', label: 'Supplier', type: 'select', options: uniq(db.receipts.map(r => r.supplier)).map(x => [x, x]), get: r => r.supplier }, { key: 'pid', label: 'Product', type: 'select', options: uniq(db.receipts.map(r => r.pid)).map(x => [x, (W.PBY[x] || db.products.find(p => p.id === x)).name]), get: r => r.pid },
          { key: 'to', label: 'Destination', type: 'select', options: uniq(db.receipts.map(r => r.to)).map(x => [x, x]), get: r => r.to }, { key: 'by', label: 'Received by', type: 'select', options: uniq(db.receipts.map(r => r.by)).map(x => [x, x]), get: r => r.by },
          { key: 'date', label: 'Date', type: 'date', get: r => r.date }, { key: 'qty', label: 'Quantity', type: 'range', get: r => r.qty }],
        columns: [{ key: 'when', label: 'When', cell: r => ({ v: r.time, sub: r.date }) }, { key: 'id', label: 'Reference', hide: 'md', cell: r => ({ v: r.id, mono: true, color: 'var(--color-neutral-300)' }) },
          { key: 'p', label: 'Product', sort: r => r.p.name, cell: r => ({ v: r.p.name, weight: 500, sub: r.p.sku }) }, { key: 'qty', label: 'Qty', align: 'right', sort: r => r.qty, cell: r => ({ v: '+' + fmt(r.qty) + ' ' + r.p.uom, color: OK }) },
          { key: 'to', label: 'To', cell: r => ({ v: r.to, mono: true }) }, { key: 'sup', label: 'Supplier', hide: 'wide', sort: r => r.supplier, cell: r => r.supplier }, { key: 'by', label: 'By', hide: 'wide', cell: r => ({ v: r.by, color: 'var(--color-neutral-300)' }) }],
        list: r => ({ icon: 'ph-box-arrow-down', iconColor: OK, title: r.p.name, sub: r.id + ' · ' + r.supplier + ' · to ' + r.to, right: '+' + fmt(r.qty), rightSub: r.date + ' ' + r.time, rightColor: OK }),
        card: r => ({ icon: 'ph-box-arrow-down', iconColor: OK, title: r.p.name, sub: r.id, metrics: [{ l: 'Qty', v: '+' + fmt(r.qty), c: OK }, { l: 'To', v: r.to }, { l: 'Supplier', v: r.supplier }] }),
        open: r => () => ctx.sheet('product', r.pid), empty: ['No receipts match', 'Adjust filters, or receive stock.'] };
    },

    transfers(ctx) {
      const { db, W } = ctx;
      const rows = db.transfers.map(r => ({ ...r, p: db.products.find(p => p.id === r.pid) || W.PBY[r.pid], route: r.from + ' → ' + r.to }));
      return { title: 'Stock Transfers', sub: 'Moves available stock between two locations as one TRANSFER transaction.', searchPh: 'Reference, product or location',
        actions: [{ label: 'Transfer stock', icon: 'ph-arrows-left-right', primary: true, fn: () => ctx.sheet('transfer') }], rows, search: r => r.id + ' ' + r.p.name + ' ' + r.route,
        stats: rs => [{ l: 'Transfers', v: rs.length, sub: rs.filter(r => r.date === '29 Sep 2026').length + ' today' }, { l: 'Units moved', v: fmt(sum(rs, r => r.qty)) }, { l: 'Putaways', v: rs.filter(r => r.from === 'RCV').length, sub: 'out of receiving' }, { l: 'To dispatch', v: rs.filter(r => r.to === 'DSP').length, c: 'var(--color-accent-300)' }, { l: 'Routes', v: uniq(rs.map(r => r.route)).length }],
        quick: { get: r => r.from === 'RCV' ? 'put' : r.to === 'DSP' ? 'dsp' : 'int', options: [['', 'All'], ['put', 'Putaway'], ['int', 'Internal'], ['dsp', 'To dispatch']] },
        filters: [{ key: 'from', label: 'From', type: 'select', options: uniq(db.transfers.map(r => r.from)).map(x => [x, x]), get: r => r.from }, { key: 'to', label: 'To', type: 'select', options: uniq(db.transfers.map(r => r.to)).map(x => [x, x]), get: r => r.to },
          { key: 'pid', label: 'Product', type: 'select', options: uniq(db.transfers.map(r => r.pid)).map(x => [x, W.PBY[x].name]), get: r => r.pid }, { key: 'by', label: 'Moved by', type: 'select', options: uniq(db.transfers.map(r => r.by)).map(x => [x, x]), get: r => r.by },
          { key: 'date', label: 'Date', type: 'date', get: r => r.date }, { key: 'qty', label: 'Quantity', type: 'range', get: r => r.qty }],
        columns: [{ key: 'when', label: 'When', cell: r => ({ v: r.time, sub: r.date }) }, { key: 'id', label: 'Reference', hide: 'wide', cell: r => ({ v: r.id, mono: true, color: 'var(--color-neutral-300)' }) },
          { key: 'p', label: 'Product', sort: r => r.p.name, cell: r => ({ v: r.p.name, weight: 500, sub: r.p.sku }) }, { key: 'qty', label: 'Qty', align: 'right', sort: r => r.qty, cell: r => fmt(r.qty) + ' ' + r.p.uom },
          { key: 'route', label: 'Route', cell: r => ({ v: r.route, mono: true }) }, { key: 'by', label: 'By', hide: 'md', cell: r => ({ v: r.by, color: 'var(--color-neutral-300)' }) }],
        list: r => ({ icon: 'ph-arrows-left-right', iconColor: 'var(--color-accent-400)', title: r.p.name, sub: r.route + ' · ' + r.by, right: fmt(r.qty), rightSub: r.date + ' ' + r.time }),
        card: r => ({ icon: 'ph-arrows-left-right', title: r.p.name, sub: r.id, metrics: [{ l: 'Qty', v: fmt(r.qty) }, { l: 'Route', v: r.route }] }),
        open: r => () => ctx.sheet('product', r.pid), empty: ['No transfers match', 'Adjust filters, or transfer stock.'] };
    },

    counts(ctx) {
      const { db, W } = ctx;
      const rows = db.counts.map(c => ({ ...c, locName: W.path(c.loc).slice(-2).join(' › '), progress: c.counted / c.items }));
      const vs = v => v === 0 ? '0' : (v > 0 ? '+' : '−') + Math.abs(v);
      const stT = r => tagC(r.status, r.status === 'Submitted' ? 'ok' : 'info');
      return { title: 'Stock Counts', sub: 'A count snapshots expected quantities at a leaf location; variances go to adjustment review.', searchPh: 'Count or location',
        actions: [{ label: 'Start count', icon: 'ph-list-checks', primary: true, fn: () => ctx.setState({ dialog: { kind: 'start' } }) }], rows, search: r => r.id + ' ' + r.loc + ' ' + r.locName,
        stats: rs => [{ l: 'Counts', v: rs.length }, { l: 'In progress', v: rs.filter(r => r.status !== 'Submitted').length, c: 'var(--color-accent-300)' }, { l: 'Submitted', v: rs.filter(r => r.status === 'Submitted').length, c: OK }, { l: 'Items counted', v: sum(rs, r => r.counted) + ' / ' + sum(rs, r => r.items) }, { l: 'Net variance', v: vs(sum(rs, r => r.variance)), sub: 'units', c: sum(rs, r => r.variance) < 0 ? BAD : null }],
        quick: { get: r => r.status, options: [['', 'All'], ['In progress', 'In progress'], ['Submitted', 'Submitted']] },
        filters: [{ key: 'loc', label: 'Location', type: 'select', options: uniq(db.counts.map(c => c.loc)).map(x => [x, x]), get: r => r.loc }, { key: 'by', label: 'Started by', type: 'select', options: uniq(db.counts.map(c => c.by)).map(x => [x, x]), get: r => r.by },
          { key: 'var', label: 'Variance', type: 'range', get: r => r.variance }, { key: 'date', label: 'Started', type: 'date', get: r => r.started }],
        columns: [{ key: 'loc', label: 'Location', sort: r => r.loc, cell: r => ({ v: r.locName, weight: 500, sub: r.id + ' · ' + r.loc }) },
          { key: 'prog', label: 'Progress', width: '160px', sort: r => r.progress, cell: r => ({ kind: 'bar', label: r.counted + '/' + r.items, w: pct(r.progress) }) },
          { key: 'var', label: 'Variance', align: 'right', sort: r => r.variance, cell: r => ({ v: vs(r.variance), color: !r.variance ? 'var(--color-neutral-400)' : r.variance > 0 ? OK : BAD }) },
          { key: 'by', label: 'Started by', hide: 'wide', cell: r => r.by }, { key: 'started', label: 'Started', hide: 'md', cell: r => ({ v: r.started, color: 'var(--color-neutral-400)' }) }, { key: 'status', label: 'Status', sort: r => r.status, cell: stT }],
        list: r => ({ icon: 'ph-list-checks', iconColor: 'var(--color-accent-400)', title: r.locName, sub: r.id + ' · ' + r.by + ' · ' + r.started, right: r.counted + '/' + r.items, rightSub: 'variance ' + vs(r.variance), tag: stT(r) }),
        card: r => ({ icon: 'ph-list-checks', title: r.locName, sub: r.id + ' · ' + r.loc, metrics: [{ l: 'Counted', v: r.counted + '/' + r.items }, { l: 'Variance', v: vs(r.variance), c: !r.variance ? null : r.variance > 0 ? OK : BAD }], tag: stT(r), bar: { w: pct(r.progress), c: 'var(--color-accent-500)' } }),
        open: r => () => ctx.sheet('count', r.id), empty: ['No counts match', 'Start a count to snapshot a location.'] };
    },

    adjustments(ctx) {
      const { db, W } = ctx;
      const all = [...db.pending.map(a => ({ ...a, status: 'Pending' })), ...db.hist];
      const rows = all.map(a => { const p = W.PBY[a.pid] || db.products.find(x => x.id === a.pid), inc = a.dir === 'INCREASE'; return { ...a, p, inc, own: a.by === 'Nomsa Mahlangu', deltaS: (inc ? '+' : '−') + fmt(a.delta), bucketS: a.bucket.toLowerCase().replace('_', ' '), days: a.days || 0 }; });
      const review = (a, mode) => ctx.setState({ dialog: { kind: 'review', mode, id: a.id }, note: '', noteErr: false });
      const stT = r => tagC(r.status, r.status === 'Pending' ? 'warn' : r.status === 'Approved' ? 'ok' : 'bad');
      const acts = r => r.status !== 'Pending' ? [] : r.own ? [] : [act('ph-x', 'Reject', () => review(r, 'reject'), { text: 'Reject' }), act('ph-check', 'Approve', () => review(r, 'approve'), { primary: true, text: 'Approve' })];
      const waitTag = r => r.status !== 'Pending' ? null : tagO(r.days === 0 ? 'today' : r.days + 'd waiting', r.days >= 3 ? 'bad' : r.days >= 1 ? 'warn' : 'neutral');
      return { title: 'Stock Adjustments', sub: 'Only an approval moves stock. You can’t approve your own requests.', searchPh: 'Product, reference or reason',
        actions: [{ label: 'Request adjustment', icon: 'ph-plus', primary: true, fn: () => FORMS.adjustment(ctx) }], rows, search: r => r.p.name + ' ' + r.id + ' ' + r.reason,
        stats: rs => { const pend = rs.filter(r => r.status === 'Pending'); return [{ l: 'Pending', v: pend.length, c: pend.length ? WARN : null, sub: pend.filter(r => r.own).length + ' are yours' }, { l: 'Oldest wait', v: pend.length ? Math.max(...pend.map(r => r.days)) + 'd' : '—', c: pend.some(r => r.days >= 3) ? BAD : null }, { l: 'Approved', v: rs.filter(r => r.status === 'Approved').length, c: OK }, { l: 'Rejected', v: rs.filter(r => r.status === 'Rejected').length }, { l: 'Net pending', v: (sum(pend, r => r.inc ? r.delta : -r.delta) >= 0 ? '+' : '−') + fmt(Math.abs(sum(pend, r => r.inc ? r.delta : -r.delta))), sub: 'units if all approved' }]; },
        quick: { default: 'Pending', get: r => r.status, options: [['Pending', 'Queue'], ['Approved', 'Approved'], ['Rejected', 'Rejected'], ['', 'All']] },
        filters: [{ key: 'bucket', label: 'Bucket', type: 'multi', options: [['ON_HAND', 'On hand'], ['DAMAGED', 'Damaged'], ['LOST', 'Lost'], ['EXPIRED', 'Expired']], get: r => r.bucket }, { key: 'dir', label: 'Direction', type: 'select', options: [['INCREASE', 'Increase'], ['DECREASE', 'Decrease']], get: r => r.dir },
          { key: 'by', label: 'Requested by', type: 'select', options: uniq(all.map(a => a.by)).map(x => [x, x]), get: r => r.by }, { key: 'loc', label: 'Location', type: 'select', options: uniq(all.map(a => a.loc)).map(x => [x, x]), get: r => r.loc },
          { key: 'days', label: 'Waiting (days)', type: 'range', get: r => r.days }, { key: 'mine', label: 'Ownership', type: 'toggle', text: 'Hide my own requests', get: r => !r.own }],
        defaultView: 'list',
        columns: [{ key: 'chg', label: 'Change', sort: r => r.inc ? r.delta : -r.delta, cell: r => ({ v: r.deltaS, color: r.inc ? OK : BAD, weight: 500, sub: r.bucketS }) },
          { key: 'p', label: 'Product', sort: r => r.p.name, cell: r => ({ v: r.p.name, weight: 500, sub: r.id + ' · ' + r.loc }) }, { key: 'reason', label: 'Reason', hide: 'wide', cell: r => ({ v: '“' + r.reason + '”', color: 'var(--color-neutral-300)' }) },
          { key: 'by', label: 'Requested', hide: 'md', sort: r => r.by, cell: r => ({ v: r.by, sub: r.when }) }, { key: 'wait', label: 'Waiting', sort: r => r.days, cell: r => waitTag(r) ? { kind: 'tag', ...waitTag(r) } : { v: r.reviewer ? 'by ' + r.reviewer : '—', color: 'var(--color-neutral-400)' } },
          { key: 'status', label: 'Status', cell: stT }, { key: 'act', label: '', width: '170px', cell: r => r.status === 'Pending' && r.own ? { v: 'Needs another reviewer', color: 'var(--color-neutral-500)' } : { kind: 'actions', actions: acts(r) } }],
        list: r => ({ icon: r.inc ? 'ph-plus-circle' : 'ph-minus-circle', iconColor: r.inc ? OK : BAD, title: r.deltaS + ' ' + r.bucketS + ' · ' + r.p.name, sub: r.loc + ' · “' + r.reason + '” · ' + r.by + (r.own && r.status === 'Pending' ? ' (you — another reviewer must approve)' : ''), tag: waitTag(r) || stT(r), actions: acts(r) }),
        card: r => ({ icon: r.inc ? 'ph-plus-circle' : 'ph-minus-circle', iconColor: r.inc ? OK : BAD, title: r.p.name, sub: r.id + ' · ' + r.loc + ' · ' + r.by, metrics: [{ l: 'Change', v: r.deltaS, c: r.inc ? OK : BAD }, { l: 'Bucket', v: r.bucketS }], tag: waitTag(r) || stT(r), actions: acts(r) }),
        open: null, empty: ['Nothing here', 'No adjustments match — the queue may be clear.'] };
    },

    packing(ctx) {
      const { db, W } = ctx; const wsBy = byId(db.workstreams);
      const rows = db.packing.map(o => { const lines = o.lines.map(l => { const p = W.PBY[l.pid]; return { ...l, p, ws: p.ws, wsName: wsBy[p.ws] ? wsBy[p.ws].name : '—' }; }); return { ...o, id: o.ref, title: o.label || 'Order ' + o.ref.slice(0, 8), lines, mine: lines.length, others: o.total - lines.length, units: sum(lines, l => l.qty), ws: uniq(lines.map(l => l.ws)), wsNames: uniq(lines.map(l => l.wsName)), locs: uniq(lines.map(l => l.loc)) }; });
      const itemsTag = r => tagO(r.mine + ' of ' + r.total + ' items', r.others ? 'info' : 'ok');
      return { title: 'Packing', sub: 'Open orders with the items you handle, oldest first. An order leaves this list once dispatched.', searchPh: 'Order or customer',
        actions: [{ label: 'Print all pick lists', icon: 'ph-printer', fn: () => window.WHA.exportPickList(rows, ctx) }], rows, search: r => r.title + ' ' + r.ref,
        stats: rs => [{ l: 'Open orders', v: rs.length }, { l: 'Lines to pick', v: sum(rs, r => r.mine) }, { l: 'Units', v: fmt(sum(rs, r => r.units)) }, { l: 'Shared orders', v: rs.filter(r => r.others).length, sub: 'other workstreams pack the rest', c: 'var(--color-accent-300)' }, { l: 'Pick locations', v: uniq(rs.flatMap(r => r.locs)).length }],
        quick: { get: r => r.others ? 'shared' : 'mine', options: [['', 'All'], ['mine', 'Only my items'], ['shared', 'Shared']] },
        filters: [{ key: 'ws', label: 'Workstream', type: 'select', options: db.workstreams.map(w => [w.id, w.name]), get: r => r.ws }, { key: 'loc', label: 'Pick location', type: 'select', options: uniq(db.packing.flatMap(o => o.lines.map(l => l.loc))).map(x => [x, x]), get: r => r.locs },
          { key: 'date', label: 'Reserved', type: 'date', get: r => r.reserved }, { key: 'units', label: 'Units', type: 'range', get: r => r.units }],
        columns: [{ key: 'order', label: 'Order', sort: r => r.title, cell: r => ({ v: r.title, weight: 500, sub: r.ref }) }, { key: 'res', label: 'Reserved', hide: 'md', sort: r => pd(r.reserved), cell: r => ({ v: r.reserved, color: 'var(--color-neutral-300)' }) },
          { key: 'items', label: 'Items', cell: r => ({ kind: 'tag', ...itemsTag(r) }) }, { key: 'units', label: 'Units', align: 'right', sort: r => r.units, cell: r => fmt(r.units) },
          { key: 'locs', label: 'Pick from', hide: 'wide', cell: r => ({ kind: 'tags', tags: r.locs.map(l => ({ v: l, fg: 'var(--color-neutral-200)', bg: 'var(--color-neutral-800)' })) }) }, { key: 'ws', label: 'Workstreams', hide: 'wide', cell: r => ({ kind: 'tags', tags: r.wsNames }) },
          { key: 'act', label: '', width: '44px', cell: r => ({ kind: 'actions', actions: [act('ph-printer', 'Print pick list', () => window.WHA.exportPickList([r], ctx))] }) }],
        list: r => ({ icon: 'ph-package', iconColor: 'var(--color-accent-400)', title: r.title, sub: 'Reserved ' + r.reserved + ' · pick from ' + r.locs.join(', '), right: fmt(r.units) + ' units', tag: itemsTag(r) }),
        card: r => ({ icon: 'ph-package', title: r.title, sub: 'Reserved ' + r.reserved, metrics: [{ l: 'Lines', v: r.mine }, { l: 'Units', v: fmt(r.units) }, { l: 'Locations', v: r.locs.length }], tag: itemsTag(r), actions: [act('ph-printer', 'Print', () => window.WHA.exportPickList([r], ctx), { text: 'Pick list' })] }),
        open: r => () => ctx.sheet('packing', r.ref), empty: ['Nothing to pack', 'No open orders include items from your warehouses or workstreams.'] };
    },

    users(ctx) {
      const { db } = ctx;
      const rows = db.users;
      const stT = r => tagC(r.status, r.status === 'Active' ? 'ok' : r.status === 'Suspended' ? 'bad' : 'neutral');
      const setSt = (u, st) => { ctx.update('users', l => l.map(x => x.email === u.email ? { ...x, status: st } : x)); ctx.toast('ok', u.name + ' ' + st.toLowerCase(), st === 'Active' ? 'They can sign in again.' : 'Signed out everywhere.'); };
      return { title: 'Users', sub: 'People who sign in to this warehouse system.', searchPh: 'Name or email',
        actions: [{ label: 'New user', icon: 'ph-user-plus', primary: true, fn: () => FORMS.user(ctx) }], rows, search: r => r.name + ' ' + r.email,
        stats: rs => [{ l: 'Users', v: rs.length }, { l: 'Active', v: rs.filter(r => r.status === 'Active').length, c: OK }, { l: 'Suspended', v: rs.filter(r => r.status === 'Suspended').length, c: rs.some(r => r.status === 'Suspended') ? BAD : null }, { l: 'Authenticator app', v: rs.filter(r => r.mfa === 'Authenticator app').length, sub: 'stronger sign-in check' }, { l: 'Multi-warehouse', v: rs.filter(r => r.whs.length > 1).length }],
        quick: { get: r => r.status, options: [['', 'All'], ['Active', 'Active'], ['Suspended', 'Suspended'], ['Inactive', 'Inactive']] },
        filters: [{ key: 'role', label: 'Role', type: 'select', options: db.roles.map(r => [r.name, r.name]), get: r => r.roles }, { key: 'wh', label: 'Warehouse', type: 'select', options: db.warehouses.map(w => [w.code, w.name]), get: r => r.whs }, { key: 'mfa', label: 'Sign-in check', type: 'select', options: [['Authenticator app', 'Authenticator app'], ['Email code', 'Email code']], get: r => r.mfa }],
        sort: { key: 'name', dir: 1 },
        columns: [{ key: 'name', label: 'User', sort: r => r.name, cell: r => ({ kind: 'avatar', v: r.name, sub: r.email, initials: r.initials }) }, { key: 'roles', label: 'Roles', hide: 'md', cell: r => ({ kind: 'tags', tags: r.roles }) },
          { key: 'whs', label: 'Warehouses', hide: 'wide', cell: r => ({ v: r.whs.join(', ') || '—', mono: true, color: 'var(--color-neutral-300)' }) }, { key: 'mfa', label: 'Sign-in check', hide: 'wide', cell: r => ({ v: r.mfa, color: 'var(--color-neutral-300)' }) },
          { key: 'status', label: 'Status', sort: r => r.status, cell: stT },
          { key: 'act', label: '', width: '100px', cell: r => ({ kind: 'actions', actions: [act('ph-pencil-simple', 'Edit', () => FORMS.user(ctx, r)), act('ph-key', 'Reset password', () => ctx.confirm('Reset password for ' + r.name + '?', 'They get an email with a reset link. Their current password stops working immediately.', 'Send reset link', false, () => ctx.toast('ok', 'Reset link sent', r.email))), r.name === 'Nomsa Mahlangu' ? null : r.status === 'Active' ? act('ph-prohibit', 'Deactivate', () => ctx.confirm('Deactivate ' + r.name + '?', 'They will no longer be able to sign in. This does not delete their history.', 'Deactivate', true, () => setSt(r, 'Inactive')), { danger: true }) : act('ph-arrow-counter-clockwise', 'Reactivate', () => setSt(r, 'Active'))] }) }],
        list: r => ({ icon: 'ph-user', title: r.name, sub: r.email + ' · ' + r.roles.join(', '), right: r.whs.join(', ') || '—', rightSub: r.mfa, tag: stT(r) }),
        card: r => ({ icon: 'ph-user-circle', title: r.name, sub: r.email, metrics: [{ l: 'Roles', v: r.roles.join(', ') }, { l: 'Warehouses', v: r.whs.join(', ') || '—' }], tag: stT(r) }),
        open: r => () => FORMS.user(ctx, r), empty: ['No users match', 'Try adjusting your search or filters.'] };
    },

    roles(ctx) {
      const { db, W } = ctx;
      const rows = db.roles.map(r => ({ ...r, n: r.perms.length, users: db.users.filter(u => u.roles.includes(r.name)).length }));
      return { title: 'Roles', sub: 'A role is a set of permission keys from the warehouse catalogue.', searchPh: 'Role name',
        actions: [{ label: 'New role', icon: 'ph-plus', primary: true, fn: () => FORMS.role(ctx) }], rows, search: r => r.name + ' ' + r.desc,
        stats: rs => [{ l: 'Roles', v: rs.length }, { l: 'System', v: rs.filter(r => r.system).length, c: 'var(--color-accent-300)' }, { l: 'Custom', v: rs.filter(r => !r.system).length }, { l: 'Permission keys', v: W.ALLP.length }, { l: 'Unassigned', v: rs.filter(r => !r.users).length, sub: 'roles with no users' }],
        quick: { get: r => r.system ? 'sys' : 'cus', options: [['', 'All'], ['sys', 'System'], ['cus', 'Custom']] },
        filters: [{ key: 'perm', label: 'Grants permission', type: 'select', options: W.ALLP.map(k => [k, k]), get: r => r.perms }, { key: 'n', label: 'Permissions', type: 'range', get: r => r.n }, { key: 'users', label: 'Users', type: 'range', get: r => r.users }],
        columns: [{ key: 'name', label: 'Role', sort: r => r.name, cell: r => ({ v: r.name, weight: 500, sub: r.system ? 'System role' : 'Custom role' }) }, { key: 'desc', label: 'Description', hide: 'md', cell: r => ({ v: r.desc || '—', color: 'var(--color-neutral-400)' }) },
          { key: 'n', label: 'Permissions', width: '160px', sort: r => r.n, cell: r => ({ kind: 'bar', label: r.n + '/' + W.ALLP.length, w: pct(r.n / W.ALLP.length) }) }, { key: 'users', label: 'Users', align: 'right', sort: r => r.users, cell: r => r.users },
          { key: 'act', label: '', width: '100px', cell: r => ({ kind: 'actions', actions: [act('ph-shield-check', 'Permissions', () => ctx.sheet('role', r.id)), act('ph-pencil-simple', 'Edit', () => FORMS.role(ctx, r)), r.system || r.users ? null : act('ph-trash', 'Delete', () => ctx.confirm('Delete role "' + r.name + '"?', 'Nobody holds this role. This cannot be undone.', 'Delete', true, () => { ctx.update('roles', l => l.filter(x => x.id !== r.id)); ctx.toast('ok', 'Role deleted', r.name); }), { danger: true })] }) }],
        list: r => ({ icon: 'ph-shield', iconColor: 'var(--color-accent-400)', title: r.name, sub: r.desc, right: r.n + ' perms', rightSub: r.users + ' users', tag: r.system ? tagO('System', 'info') : null }),
        card: r => ({ icon: 'ph-shield', title: r.name, sub: r.desc, metrics: [{ l: 'Permissions', v: r.n + '/' + W.ALLP.length }, { l: 'Users', v: r.users }], tag: r.system ? tagO('System', 'info') : tagO('Custom', 'neutral'), bar: { w: pct(r.n / W.ALLP.length), c: 'var(--color-accent-500)' } }),
        open: r => () => ctx.sheet('role', r.id), empty: ['No roles match', ''] };
    },

    audit(ctx) {
      const { W } = ctx;
      const rows = W.AUDIT.map(a => ({ ...a, id: a.i, whenS: a.date + ' ' + a.time }));
      const aT = r => tagC(r.action, W.ACTION_TONE[r.action]);
      return { title: 'Audit Log', sub: 'Every write, newest first. Rows can be attributed to a user or an API key.', searchPh: 'Entity ID, entity or person',
        rows, search: r => r.who + ' ' + r.entity + ' ' + (r.entityId || '') + ' ' + r.action,
        stats: rs => [{ l: 'Entries', v: rs.length, sub: 'of 418 on the server' }, { l: 'People', v: uniq(rs.filter(r => !r.api).map(r => r.who)).length }, { l: 'API calls', v: rs.filter(r => r.api).length, c: 'var(--color-accent-300)' }, { l: 'Creates', v: rs.filter(r => r.action === 'CREATE').length }, { l: 'Updates', v: rs.filter(r => r.action === 'UPDATE').length }, { l: 'Deletes', v: rs.filter(r => r.action === 'DELETE').length, c: rs.some(r => r.action === 'DELETE') ? BAD : null }],
        quick: { get: r => r.action, options: [['', 'All'], ['CREATE', 'Create'], ['UPDATE', 'Update'], ['DELETE', 'Delete'], ['APPROVE', 'Approve']] },
        filters: [{ key: 'entity', label: 'Entity', type: 'select', options: uniq(W.AUDIT.map(a => a.entity)).map(x => [x, x]), get: r => r.entity }, { key: 'who', label: 'Who', type: 'select', options: uniq(W.AUDIT.map(a => a.who)).map(x => [x, x]), get: r => r.who },
          { key: 'src', label: 'Source', type: 'select', options: [['user', 'User'], ['api', 'API key']], get: r => r.api ? 'api' : 'user' }, { key: 'date', label: 'Date', type: 'date', get: r => r.date }],
        columns: [{ key: 'when', label: 'When', sort: r => pd(r.whenS), cell: r => ({ v: r.time, sub: r.date }) }, { key: 'who', label: 'Who', sort: r => r.who, cell: r => ({ v: r.who, sub: r.api ? 'API key' : '' }) }, { key: 'action', label: 'Action', sort: r => r.action, cell: aT },
          { key: 'entity', label: 'Entity', hide: 'md', sort: r => r.entity, cell: r => ({ v: r.entity, mono: true, color: 'var(--color-neutral-300)' }) }, { key: 'eid', label: 'Entity ID', hide: 'wide', cell: r => ({ v: r.entityId || '—', mono: true, color: 'var(--color-neutral-400)' }) }],
        sort: { key: 'when', dir: -1 },
        list: r => ({ icon: r.api ? 'ph-key' : 'ph-user', iconColor: r.api ? 'var(--color-accent-400)' : 'var(--color-neutral-500)', title: r.action + ' · ' + r.entity, sub: (r.entityId || '—') + ' · ' + r.who, right: r.time, rightSub: r.date, tag: null }),
        card: r => ({ icon: r.api ? 'ph-key' : 'ph-clock-counter-clockwise', title: r.action + ' ' + r.entity, sub: r.entityId || '—', metrics: [{ l: 'Who', v: r.who }, { l: 'When', v: r.date + ' ' + r.time }], tag: aT(r) }),
        open: r => () => ctx.setState({ dialog: { kind: 'audit', i: r.i } }), footNote: 'Page 1 of 42 · 418 entries on the server', empty: ['No entries match', 'Try widening or clearing the filters.'] };
    },

    reports(ctx) {
      const { W } = ctx; const last = ctx.s.exports || {};
      const rows = W.REPORTS.map(r => ({ ...r, nRows: window.WHA.report(r.id, ctx).rows.length, last: last[r.id] || '' }));
      const ex = (r, kind) => () => window.WHA.exportReport(r.id, kind, ctx);
      return { title: 'Reports', sub: 'Every report exports to PDF and Excel with your logo in the header.', searchPh: 'Report name',
        actions: [{ label: 'Branding', icon: 'ph-image', fn: () => ctx.setState({ screen: 'settings', sec: 'branding' }) }], rows, search: r => r.name + ' ' + r.desc,
        stats: rs => [{ l: 'Reports', v: rs.length }, { l: 'Rows available', v: fmt(sum(rs, r => r.nRows)) }, { l: 'Exported this session', v: Object.keys(last).length, c: 'var(--color-accent-300)' }, { l: 'Formats', v: 'PDF · Excel' }, { l: 'Logo', v: ctx.s.logo ? 'Custom' : 'Default', sub: 'change in Settings' }],
        quick: { get: r => r.cat, options: [['', 'All']].concat(uniq(W.REPORTS.map(r => r.cat)).map(c => [c, c])) },
        filters: [{ key: 'cat', label: 'Category', type: 'multi', options: uniq(W.REPORTS.map(r => r.cat)).map(c => [c, c]), get: r => r.cat }, { key: 'rows', label: 'Rows', type: 'range', get: r => r.nRows }, { key: 'exp', label: 'History', type: 'toggle', text: 'Exported this session', get: r => !!r.last }],
        columns: [{ key: 'name', label: 'Report', sort: r => r.name, cell: r => ({ v: r.name, weight: 500, sub: r.desc }) }, { key: 'cat', label: 'Category', hide: 'md', sort: r => r.cat, cell: r => tagC(r.cat, 'info') },
          { key: 'rows', label: 'Rows', align: 'right', sort: r => r.nRows, cell: r => r.nRows }, { key: 'last', label: 'Last export', hide: 'wide', cell: r => ({ v: r.last || 'Not yet', color: r.last ? 'var(--color-text)' : 'var(--color-neutral-500)' }) },
          { key: 'act', label: '', width: '170px', cell: r => ({ kind: 'actions', actions: [act('ph-file-pdf', 'PDF', ex(r, 'pdf'), { text: 'PDF' }), act('ph-microsoft-excel-logo', 'Excel', ex(r, 'xlsx'), { text: 'Excel' })] }) }],
        list: r => ({ icon: r.icon, iconColor: 'var(--color-accent-400)', title: r.name, sub: r.desc, right: r.nRows + ' rows', rightSub: r.last || r.cat, actions: [act('ph-file-pdf', 'PDF', ex(r, 'pdf'), { text: 'PDF' }), act('ph-microsoft-excel-logo', 'Excel', ex(r, 'xlsx'), { text: 'Excel' })] }),
        card: r => ({ icon: r.icon, title: r.name, sub: r.desc, metrics: [{ l: 'Rows', v: r.nRows }, { l: 'Category', v: r.cat }], actions: [act('ph-file-pdf', 'PDF', ex(r, 'pdf'), { text: 'PDF' }), act('ph-microsoft-excel-logo', 'Excel', ex(r, 'xlsx'), { text: 'Excel' })] }),
        open: r => () => ctx.sheet('report', r.id), empty: ['No reports match', ''] };
    },
  };

  // ─── Reports: data ─────────────────────────────────────────────────
  function report(id, ctx) {
    const { W, db } = ctx; const idx = locIndex(db.locs);
    const P = db.products; const def = W.REPORTS.find(r => r.id === id) || {};
    const base = { id, title: def.name, desc: def.desc };
    const C = (h, type, w) => ({ h, type: type || 'text', w: w || 14 });
    if (id === 'soh') return { ...base, columns: [C('SKU', 'text', 10), C('Product', 'text', 26), C('Location', 'text', 10), C('Path', 'text', 30), C('On hand', 'num', 10), C('Reserved', 'num', 10), C('Available', 'num', 10)],
      rows: P.flatMap(p => (W.BD[p.id] || []).map(b => [p.sku, p.name, b.loc.code, W.path(b.loc.id).join(' › '), b.onHand, b.reserved, b.onHand - b.reserved])), totalsFrom: 4 };
    if (id === 'low') return { ...base, columns: [C('SKU', 'text', 10), C('Product', 'text', 28), C('UOM', 'text', 8), C('On hand', 'num', 10), C('Minimum', 'num', 10), C('Shortfall', 'num', 10)],
      rows: P.filter(p => p.status === 'Active' && p.stock < p.min).map(p => [p.sku, p.name, p.uom, p.stock, p.min, p.min - p.stock]), totalsFrom: 5 };
    if (id === 'val') return { ...base, columns: [C('SKU', 'text', 10), C('Product', 'text', 28), C('On hand', 'num', 10), C('Cost price', 'money', 12), C('Value', 'money', 14)],
      rows: P.filter(p => p.cost && p.status === 'Active').map(p => [p.sku, p.name, p.stock, p.cost, p.stock * p.cost]), totalsFrom: 4, note: P.filter(p => !p.cost).length + ' product(s) without a cost price excluded.' };
    if (id === 'mov') return { ...base, columns: [C('Date', 'text', 14), C('Type', 'text', 10), C('Reference', 'text', 16), C('Product', 'text', 26), C('Qty', 'num', 8), C('From', 'text', 10), C('To', 'text', 10), C('By', 'text', 16)],
      rows: [...db.receipts.map(r => [r.date + ' ' + r.time, 'RECEIVE', r.id, (W.PBY[r.pid] || {}).name || r.pid, r.qty, '', r.to, r.by]), ...db.transfers.map(t => [t.date + ' ' + t.time, 'TRANSFER', t.id, W.PBY[t.pid].name, t.qty, t.from, t.to, t.by])].sort((a, b) => pd(b[0]) - pd(a[0])) };
    if (id === 'adj') return { ...base, columns: [C('Reference', 'text', 10), C('Product', 'text', 24), C('Change', 'num', 8), C('Bucket', 'text', 10), C('Location', 'text', 10), C('Status', 'text', 10), C('Requested by', 'text', 16), C('Reviewer', 'text', 16)],
      rows: [...db.pending.map(a => ({ ...a, status: 'Pending' })), ...db.hist].map(a => [a.id, W.PBY[a.pid].name, (a.dir === 'INCREASE' ? 1 : -1) * a.delta, a.bucket.replace('_', ' ').toLowerCase(), a.loc, a.status, a.by || '', a.reviewer || '']) };
    if (id === 'cnt') return { ...base, columns: [C('Count', 'text', 10), C('Location', 'text', 12), C('Started', 'text', 18), C('Started by', 'text', 16), C('Items', 'num', 8), C('Counted', 'num', 8), C('Variance', 'num', 9), C('Status', 'text', 12)],
      rows: db.counts.map(c => [c.id, c.loc, c.started, c.by, c.items, c.counted, c.variance, c.status]), totalsFrom: 4 };
    if (id === 'util') return { ...base, columns: [C('Code', 'text', 10), C('Location', 'text', 30), C('Type', 'text', 10), C('Units', 'num', 10), C('Capacity', 'num', 10), C('Fill %', 'pct', 9)],
      rows: idx.list.filter(l => l.leaf && !l.inactive).map(l => { const u = idx.units(l.id), c = idx.cap(l.id); return [l.code, idx.path(l.id).join(' › '), l.type, u, c, c ? u / c : 0]; }), totalsFrom: 3 };
    return { ...base, columns: [], rows: [] };
  }
  const fmtCell = (v, type) => v == null || v === '' ? '' : type === 'num' ? fmt(v) : type === 'money' ? money(v) : type === 'pct' ? Math.round(v * 100) + '%' : String(v);
  function totals(rep) {
    if (rep.totalsFrom == null || !rep.rows.length) return null;
    return rep.columns.map((c, i) => i === 0 ? 'Total' : i >= rep.totalsFrom && (c.type === 'num' || c.type === 'money') ? sum(rep.rows, r => r[i]) : '');
  }
  function preview(id, ctx) {
    const rep = report(id, ctx); const t = totals(rep);
    return { ...rep, head: rep.columns.map(c => ({ h: c.h, align: c.type === 'text' ? 'left' : 'right' })),
      body: rep.rows.slice(0, 14).map(r => ({ cells: r.map((v, i) => ({ v: fmtCell(v, rep.columns[i].type), align: rep.columns[i].type === 'text' ? 'left' : 'right' })) })),
      foot: t ? t.map((v, i) => ({ v: typeof v === 'number' ? fmtCell(v, rep.columns[i].type) : v, align: rep.columns[i].type === 'text' ? 'left' : 'right' })) : [], hasFoot: !!t,
      more: rep.rows.length > 14 ? `+ ${rep.rows.length - 14} more rows in the export` : '', hasMore: rep.rows.length > 14, n: rep.rows.length, hasNote: !!rep.note, note: rep.note || '' };
  }

  // ─── Reports: export ───────────────────────────────────────────────
  const loaded = {};
  function loadScript(src) {
    if (!loaded[src]) loaded[src] = new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = () => rej(new Error('Could not load ' + src)); document.head.appendChild(s); });
    return loaded[src];
  }
  function defaultLogo() {
    const c = document.createElement('canvas'); c.width = c.height = 256; const g = c.getContext('2d');
    g.fillStyle = '#2b2741'; g.beginPath(); g.roundRect(8, 8, 240, 240, 56); g.fill();
    g.strokeStyle = '#b5abfc'; g.lineWidth = 14; g.lineJoin = 'round'; g.lineCap = 'round';
    g.beginPath(); g.moveTo(52, 118); g.lineTo(128, 64); g.lineTo(204, 118); g.stroke();
    g.beginPath(); g.moveTo(72, 110); g.lineTo(72, 196); g.lineTo(184, 196); g.lineTo(184, 110); g.stroke();
    g.lineWidth = 10; g.beginPath(); g.moveTo(102, 196); g.lineTo(102, 142); g.lineTo(154, 142); g.lineTo(154, 196); g.moveTo(102, 160); g.lineTo(154, 160); g.moveTo(102, 178); g.lineTo(154, 178); g.stroke();
    return c.toDataURL('image/png');
  }
  async function logoPng(custom) {
    if (!custom) return defaultLogo();
    return await new Promise(res => { const img = new Image(); img.onload = () => { const c = document.createElement('canvas'); const k = 256 / Math.max(img.width, img.height); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); res(c.toDataURL('image/png')); }; img.onerror = () => res(defaultLogo()); img.src = custom; });
  }
  const stamp = () => new Date().toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  function download(blob, name) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }
  const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

  async function pdfDoc(rep, ctx, orientation) {
    await loadScript('https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js');
    await loadScript('https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.8.2/jspdf.plugin.autotable.min.js');
    const { jsPDF } = window.jspdf; const doc = new jsPDF({ orientation: orientation || (rep.columns.length > 6 ? 'landscape' : 'portrait'), unit: 'pt', format: 'a4' });
    const W_ = doc.internal.pageSize.getWidth(); const logo = await logoPng(ctx.s.logo); const company = ctx.s.company || 'Warehouse System';
    const head = () => { doc.addImage(logo, 'PNG', 40, 30, 36, 36); doc.setFont('helvetica', 'bold'); doc.setFontSize(13); doc.setTextColor(31, 33, 39); doc.text(company, 86, 45); doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(107, 111, 128); doc.text('Main Warehouse (JHB-01) · Generated ' + stamp() + ' by Nomsa Mahlangu', 86, 59); doc.setDrawColor(214, 217, 231); doc.line(40, 78, W_ - 40, 78); };
    head(); doc.setFont('helvetica', 'bold'); doc.setFontSize(17); doc.setTextColor(31, 33, 39); doc.text(rep.title, 40, 104);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(107, 111, 128); doc.text((rep.desc || '') + (rep.note ? '  ' + rep.note : ''), 40, 119);
    return { doc, head, W_ };
  }
  async function exportReport(id, kind, ctx) {
    const rep = report(id, ctx); const t = totals(rep); const name = slug(rep.title) + '-' + new Date().toISOString().slice(0, 10);
    ctx.toast('info', 'Preparing ' + (kind === 'pdf' ? 'PDF' : 'Excel') + '…', rep.title + ' · ' + rep.rows.length + ' rows', null, 2500);
    try {
      if (kind === 'pdf') {
        const { doc, head, W_ } = await pdfDoc(rep, ctx);
        const colStyles = {}; rep.columns.forEach((c, i) => { if (c.type !== 'text') colStyles[i] = { halign: 'right' }; });
        doc.autoTable({ startY: 132, head: [rep.columns.map(c => c.h)], body: rep.rows.map(r => r.map((v, i) => fmtCell(v, rep.columns[i].type))), foot: t ? [t.map((v, i) => typeof v === 'number' ? fmtCell(v, rep.columns[i].type) : v)] : undefined,
          styles: { font: 'helvetica', fontSize: 8.5, cellPadding: 5, textColor: [31, 33, 39], lineColor: [226, 229, 240], lineWidth: 0.5 }, headStyles: { fillColor: [43, 39, 65], textColor: [245, 244, 255], fontStyle: 'bold' },
          footStyles: { fillColor: [236, 238, 247], textColor: [31, 33, 39], fontStyle: 'bold' }, alternateRowStyles: { fillColor: [248, 249, 253] }, columnStyles: colStyles, margin: { left: 40, right: 40, top: 92 },
          didDrawPage: d => { if (d.pageNumber > 1) head(); } });
        const n = doc.internal.getNumberOfPages();
        for (let i = 1; i <= n; i++) { doc.setPage(i); doc.setFontSize(8); doc.setTextColor(147, 151, 171); doc.text((ctx.s.company || 'Warehouse System') + ' · ' + rep.title, 40, doc.internal.pageSize.getHeight() - 24); doc.text('Page ' + i + ' of ' + n, W_ - 40, doc.internal.pageSize.getHeight() - 24, { align: 'right' }); }
        doc.save(name + '.pdf');
      } else {
        await loadScript('https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js');
        const wb = new window.ExcelJS.Workbook(); wb.creator = ctx.s.company || 'Warehouse System'; wb.created = new Date();
        const ws = wb.addWorksheet(rep.title.slice(0, 31), { views: [{ state: 'frozen', ySplit: 6 }], pageSetup: { orientation: rep.columns.length > 6 ? 'landscape' : 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0 } });
        const n = rep.columns.length; const logo = await logoPng(ctx.s.logo);
        ws.getRow(1).height = 30; ws.getRow(2).height = 16;
        ws.addImage(wb.addImage({ base64: logo, extension: 'png' }), { tl: { col: 0.15, row: 0.15 }, ext: { width: 40, height: 40 } });
        ws.mergeCells(1, 2, 1, n); Object.assign(ws.getCell(1, 2), { value: ctx.s.company || 'Warehouse System' }); ws.getCell(1, 2).font = { bold: true, size: 14, color: { argb: 'FF1F2127' } }; ws.getCell(1, 2).alignment = { vertical: 'middle' };
        ws.mergeCells(2, 2, 2, n); ws.getCell(2, 2).value = 'Main Warehouse (JHB-01) · Generated ' + stamp() + ' by Nomsa Mahlangu'; ws.getCell(2, 2).font = { size: 9, color: { argb: 'FF6B6F80' } };
        ws.mergeCells(4, 1, 4, n); ws.getCell(4, 1).value = rep.title; ws.getCell(4, 1).font = { bold: true, size: 15, color: { argb: 'FF1F2127' } };
        ws.mergeCells(5, 1, 5, n); ws.getCell(5, 1).value = (rep.desc || '') + (rep.note ? '  ' + rep.note : ''); ws.getCell(5, 1).font = { size: 9, color: { argb: 'FF6B6F80' } };
        const hr = ws.getRow(6); rep.columns.forEach((c, i) => { const cl = hr.getCell(i + 1); cl.value = c.h; cl.font = { bold: true, color: { argb: 'FFF5F4FF' } }; cl.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2B2741' } }; cl.alignment = { horizontal: c.type === 'text' ? 'left' : 'right', vertical: 'middle' }; }); hr.height = 20;
        rep.rows.forEach((r, ri) => { const row = ws.getRow(7 + ri); r.forEach((v, i) => { const c = rep.columns[i], cl = row.getCell(i + 1); cl.value = v; if (c.type === 'num') cl.numFmt = '#,##0'; if (c.type === 'money') cl.numFmt = '#,##0.00'; if (c.type === 'pct') cl.numFmt = '0%'; if (ri % 2) cl.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF8F9FD' } }; cl.border = { bottom: { style: 'thin', color: { argb: 'FFE2E5F0' } } }; }); });
        if (t) { const fr = ws.getRow(7 + rep.rows.length); t.forEach((v, i) => { const c = rep.columns[i], cl = fr.getCell(i + 1); cl.value = v === '' ? null : v; cl.font = { bold: true }; cl.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFECEEF7' } }; if (c.type === 'num') cl.numFmt = '#,##0'; if (c.type === 'money') cl.numFmt = '#,##0.00'; }); }
        rep.columns.forEach((c, i) => { ws.getColumn(i + 1).width = c.w; });
        ws.autoFilter = { from: { row: 6, column: 1 }, to: { row: 6 + rep.rows.length, column: n } };
        const buf = await wb.xlsx.writeBuffer();
        download(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), name + '.xlsx');
      }
      ctx.setState(st => ({ exports: { ...(st.exports || {}), [id]: (kind === 'pdf' ? 'PDF' : 'Excel') + ' · ' + new Date().toTimeString().slice(0, 5) } }));
      ctx.toast('ok', (kind === 'pdf' ? 'PDF' : 'Excel') + ' downloaded', name + (kind === 'pdf' ? '.pdf' : '.xlsx'));
    } catch (e) { ctx.toast('bad', 'Export failed', e.message || String(e)); }
  }
  async function exportPickList(orders, ctx) {
    ctx.toast('info', 'Preparing pick list…', orders.length + ' order' + (orders.length === 1 ? '' : 's'), null, 2500);
    try {
      const rep = { title: 'Pick list', desc: orders.length + ' open order(s) · only lines your workstreams pack', columns: [] };
      const { doc, head } = await pdfDoc(rep, ctx, 'portrait');
      let y = 136;
      orders.forEach(o => {
        doc.autoTable({ startY: y, head: [[{ content: o.title + '   ·   reserved ' + o.reserved + '   ·   ' + o.lines.length + ' of ' + o.total + ' items', colSpan: 5 }], ['☐', 'Qty', 'Product', 'SKU', 'Pick from']],
          body: o.lines.map(l => ['', fmt(l.qty) + ' ' + l.p.uom, l.p.name, l.p.sku, l.loc]), styles: { font: 'helvetica', fontSize: 9, cellPadding: 5, lineColor: [226, 229, 240], lineWidth: 0.5 },
          headStyles: { fillColor: [43, 39, 65], textColor: [245, 244, 255] }, columnStyles: { 0: { cellWidth: 22 }, 1: { cellWidth: 70, fontStyle: 'bold' } }, margin: { left: 40, right: 40, top: 92 }, didDrawPage: d => { if (d.pageNumber > 1) head(); } });
        y = doc.lastAutoTable.finalY + 18;
      });
      doc.save('pick-list-' + new Date().toISOString().slice(0, 10) + '.pdf');
      ctx.toast('ok', 'Pick list downloaded', orders.map(o => o.title).join(', '));
    } catch (e) { ctx.toast('bad', 'Export failed', e.message || String(e)); }
  }

  window.WHA = { applyTheme, THEMES, buildList, locIndex, FORMS, report, preview, exportReport, exportPickList, defaultLogo, fmt, money, pct, sum, byId, uniq };
})();
