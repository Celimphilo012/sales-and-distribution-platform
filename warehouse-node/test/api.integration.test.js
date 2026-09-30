'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const ExcelJS = require('exceljs');
const { createTestApp, client, loginAs, multipart, uid, settle } = require('./helpers');

// 1x1 transparent PNG.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);

describe('warehouse API (Express port)', () => {
  let app;
  let api; // admin client
  const run = uid();

  // Shared fixtures, built once.
  const fx = {};

  before(async () => {
    app = await createTestApp();
    const { accessToken } = await loginAs(app);
    api = client(app, { token: accessToken });

    const warehouse = (await api.post('/warehouses', { name: `WH ${run}`, code: `WH-${run}` })).json;
    fx.warehouseId = warehouse.id;
    const loc = async (name, code) =>
      (await api.post('/locations', { warehouseId: warehouse.id, name, code: `${code}-${run}`, locationType: 'BIN' })).json;
    fx.locA = await loc('Bin A', 'A');
    fx.locB = await loc('Bin B', 'B');

    const workstream = (await api.post('/workstreams', { warehouseId: warehouse.id, name: `WS ${run}`, code: `WS-${run}` })).json;
    fx.workstream = workstream;
    fx.category = (await api.post('/categories', { name: `Cat ${run}`, workstreamId: workstream.id })).json;
    fx.product = (
      await api.post('/products', {
        sku: `SKU-${run}`,
        name: `Product ${run}`,
        categoryId: fx.category.id,
        sellingPrice: 10.5,
        costPrice: 4,
        uom: 'EACH',
      })
    ).json;
  });

  after(async () => {
    await app.close();
  });

  const balanceOf = async (productId, locationId) => {
    const rows = (await api.get(`/inventory/balances?productId=${productId}&locationId=${locationId}`)).json;
    return rows[0] ? { onHand: Number(rows[0].onHand), reserved: Number(rows[0].reserved), available: Number(rows[0].available) } : null;
  };

  describe('setup sanity', () => {
    it('created the fixtures', () => {
      for (const key of ['locA', 'locB', 'workstream', 'category', 'product']) assert.ok(fx[key]?.id, `${key} missing`);
    });
  });

  describe('authentication', () => {
    it('logs in and returns tokens + the user', async () => {
      const res = await app.inject({ method: 'POST', url: '/auth/login', payload: { email: 'admin@test.local', password: 'TestPass123!' } });
      assert.equal(res.statusCode, 200);
      const body = res.json();
      assert.ok(body.accessToken && body.refreshToken);
      assert.equal(body.user.email, 'admin@test.local');
    });

    it('rejects a wrong password with 401 and the standard error shape', async () => {
      const res = await client(app).post('/auth/login', { email: 'admin@test.local', password: 'nope' });
      assert.equal(res.status, 401);
      assert.deepEqual(Object.keys(res.json).sort(), ['error', 'message', 'path', 'statusCode', 'timestamp']);
    });

    it('rotates refresh tokens: the old one stops working', async () => {
      const first = await loginAs(app);
      const rotated = await client(app).post('/auth/refresh', { refreshToken: first.refreshToken });
      assert.equal(rotated.status, 200);
      assert.notEqual(rotated.json.refreshToken, first.refreshToken);

      const reuse = await client(app).post('/auth/refresh', { refreshToken: first.refreshToken });
      assert.equal(reuse.status, 401);
    });

    it('logout revokes the refresh token (and is idempotent)', async () => {
      const session = await loginAs(app);
      assert.equal((await client(app).post('/auth/logout', { refreshToken: session.refreshToken })).status, 200);
      assert.equal((await client(app).post('/auth/refresh', { refreshToken: session.refreshToken })).status, 401);
      assert.equal((await client(app).post('/auth/logout', { refreshToken: session.refreshToken })).status, 200);
    });

    it('/auth/me returns the caller with effective permissions', async () => {
      const me = (await api.get('/auth/me')).json;
      assert.equal(me.email, 'admin@test.local');
      assert.ok(me.permissions.includes('products.manage'));
      assert.ok(me.roles.some((r) => r.name === 'ADMIN'));
    });

    it('answers 401 before it ever validates the body (guards run first)', async () => {
      const res = await client(app).post('/products', { garbage: true });
      assert.equal(res.status, 401);
    });
  });

  describe('validation', () => {
    it('rejects unknown properties (forbidNonWhitelisted)', async () => {
      const res = await api.post('/warehouses', { name: 'x', code: 'y', hacker: 1 });
      assert.equal(res.status, 400);
      assert.ok(res.json.message.includes('property hacker should not exist'));
    });

    it('rejects money with more than 2 decimals but accepts 2', async () => {
      const base = { sku: `V-${uid()}`, name: 'v', categoryId: fx.category.id, uom: 'EACH' };
      assert.equal((await api.post('/products', { ...base, sellingPrice: 10.999 })).status, 400);
      const ok = await api.post('/products', { ...base, sellingPrice: 19.99 });
      assert.equal(ok.status, 201);
      assert.equal(ok.json.sellingPrice, '19.99');
    });

    it('rejects a non-positive selling price', async () => {
      const res = await api.post('/products', { sku: `V-${uid()}`, name: 'v', categoryId: fx.category.id, uom: 'EACH', sellingPrice: 0 });
      assert.equal(res.status, 400);
    });

    it('409 on a duplicate SKU', async () => {
      const res = await api.post('/products', { sku: fx.product.sku, name: 'dup', categoryId: fx.category.id, uom: 'EACH', sellingPrice: 1 });
      assert.equal(res.status, 409);
    });

    it('malformed uuid param keeps the original message', async () => {
      const res = await api.get('/products/not-a-uuid');
      assert.equal(res.status, 400);
      assert.equal(res.json.message, 'Validation failed (uuid is expected)');
    });

    it('unknown routes 404 in the standard shape', async () => {
      const res = await api.get('/definitely-not-a-route');
      assert.equal(res.status, 404);
      assert.equal(res.json.message, 'Cannot GET /definitely-not-a-route');
    });

    it('tolerates an empty body on a JSON POST', async () => {
      const key = (await api.post('/api-keys', { name: `empty-${uid()}`, scopes: ['catalogue:read'] })).json;
      const res = await api.request('POST', `/api-keys/${key.id}/revoke`, { headers: { 'content-type': 'application/json' } });
      assert.equal(res.status, 201);
      assert.equal(res.json.isActive, false);
    });
  });

  describe('permissions are database-driven, and the cache never outlives a change', () => {
    it('grant and revoke take effect on the very next request', async () => {
      const role = (await api.post('/roles', { name: `R-${uid()}` })).json;
      const email = `u-${uid()}@test.local`;
      const user = (await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'Temp User', roleIds: [role.id] })).json;
      assert.equal(user.email, email);
      const { accessToken } = await loginAs(app, { email, password: 'Passw0rd!x' });
      const asUser = client(app, { token: accessToken });

      assert.equal((await asUser.get('/products')).status, 403); // primes the cached (empty) permission set

      const perms = (await api.get('/permissions')).json;
      const view = perms.find((p) => p.key === 'catalogue.view');
      await api.put(`/roles/${role.id}/permissions`, { permissionIds: [view.id] });
      assert.equal((await asUser.get('/products')).status, 200, 'grant must be visible immediately');

      await api.put(`/roles/${role.id}/permissions`, { permissionIds: [] });
      assert.equal((await asUser.get('/products')).status, 403, 'revoke must be visible immediately');
    });

    it('permission checks use permission keys, and 403 has the standard shape', async () => {
      const role = (await api.post('/roles', { name: `R-${uid()}` })).json;
      const email = `u-${uid()}@test.local`;
      await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'No Perms', roleIds: [role.id] });
      const { accessToken } = await loginAs(app, { email, password: 'Passw0rd!x' });
      const res = await client(app, { token: accessToken }).get('/users');
      assert.equal(res.status, 403);
      assert.equal(res.json.message, 'Insufficient permissions');
    });

    it('a user can change their own password with the current one, and not without it', async () => {
      const email = `pw-${uid()}@test.local`;
      await api.post('/users', { email, password: 'OldPassw0rd!', fullName: 'Pw User' });
      const { accessToken } = await loginAs(app, { email, password: 'OldPassw0rd!' });
      const me = client(app, { token: accessToken });

      assert.equal((await me.patch('/users/me/password', { currentPassword: 'wrong', newPassword: 'NewPassw0rd!' })).status, 401);
      assert.equal((await me.patch('/users/me/password', { currentPassword: 'OldPassw0rd!', newPassword: 'NewPassw0rd!' })).status, 200);
      assert.equal((await client(app).post('/auth/login', { email, password: 'OldPassw0rd!' })).status, 401);
      assert.equal((await client(app).post('/auth/login', { email, password: 'NewPassw0rd!' })).status, 200);
    });
  });

  describe('catalogue reads reflect writes immediately (cache invalidation)', () => {
    it('a new product appears in a list that was already cached', async () => {
      const before = (await api.get('/products')).json.length;
      const hitsBefore = app.cache.stats.hits;
      await api.get('/products');
      assert.ok(app.cache.stats.hits > hitsBefore, 'second identical list read should be a cache hit');

      const created = (await api.post('/products', { sku: `NEW-${uid()}`, name: 'Fresh', categoryId: fx.category.id, uom: 'EACH', sellingPrice: 3 })).json;
      const after = (await api.get('/products')).json;
      assert.equal(after.length, before + 1);
      assert.ok(after.some((p) => p.id === created.id));
    });

    it('an edit is visible on the single-product read', async () => {
      await api.get(`/products/${fx.product.id}`); // prime
      await api.patch(`/products/${fx.product.id}`, { name: `Renamed ${run}` });
      assert.equal((await api.get(`/products/${fx.product.id}`)).json.name, `Renamed ${run}`);
      fx.product.name = `Renamed ${run}`;
    });

    it('soft-deleting hides a product from the default list but keeps the row', async () => {
      const p = (await api.post('/products', { sku: `DEL-${uid()}`, name: 'Bye', categoryId: fx.category.id, uom: 'EACH', sellingPrice: 3 })).json;
      await api.get('/products'); // prime
      const del = await api.delete(`/products/${p.id}`);
      assert.equal(del.json.status, 'INACTIVE');
      assert.ok(!(await api.get('/products')).json.some((x) => x.id === p.id));
      assert.ok((await api.get('/products?includeInactive=true')).json.some((x) => x.id === p.id));
    });

    it('product attributes: replace, keep on omit, clear on []', async () => {
      const types = (await api.get('/attribute-types')).json;
      const colour = types.find((t) => t.code === 'COLOUR');
      const weight = types.find((t) => t.code === 'WEIGHT');
      const p = (await api.post('/products', { sku: `ATTR-${uid()}`, name: 'Attr', categoryId: fx.category.id, uom: 'EACH', sellingPrice: 3, attributes: [{ attributeTypeId: colour.id, value: 'Red' }, { attributeTypeId: weight.id, value: 2 }] })).json;
      assert.equal(p.attributes.length, 2);
      assert.equal(p.attributes.find((a) => a.attributeType.code === 'WEIGHT').value, '2');

      assert.equal((await api.patch(`/products/${p.id}`, { name: 'Attr2' })).json.attributes.length, 2);
      assert.equal((await api.patch(`/products/${p.id}`, { attributes: [] })).json.attributes.length, 0);
      const bad = await api.patch(`/products/${p.id}`, { attributes: [{ attributeTypeId: weight.id, value: 'heavy' }] });
      assert.equal(bad.status, 400);
    });

    it('sub-category rules: same workstream, no cycles', async () => {
      const child = (await api.post('/categories', { name: `Child ${uid()}`, workstreamId: fx.workstream.id, parentId: fx.category.id })).json;
      const cycle = await api.patch(`/categories/${fx.category.id}`, { parentId: child.id });
      assert.equal(cycle.status, 409);
      const self = await api.patch(`/categories/${fx.category.id}`, { parentId: fx.category.id });
      assert.equal(self.status, 400);
    });
  });

  describe('workstream scoping', () => {
    it('a scoped manager only sees and edits their own workstream', async () => {
      const otherWs = (await api.post('/workstreams', { warehouseId: fx.warehouseId, name: `Other ${uid()}`, code: `O-${uid()}` })).json;
      const otherCat = (await api.post('/categories', { name: `OC ${uid()}`, workstreamId: otherWs.id })).json;

      const perms = (await api.get('/permissions')).json;
      const role = (await api.post('/roles', { name: `WM-${uid()}` })).json;
      await api.put(`/roles/${role.id}/permissions`, { permissionIds: perms.filter((p) => ['catalogue.view', 'products.manage'].includes(p.key)).map((p) => p.id) });
      const email = `wm-${uid()}@test.local`;
      const user = (await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'WS Manager', roleIds: [role.id] })).json;
      await api.put(`/users/${user.id}/warehouses`, { warehouseIds: [fx.warehouseId] }); // access is deny-by-default
      const { accessToken } = await loginAs(app, { email, password: 'Passw0rd!x' });
      const mgr = client(app, { token: accessToken });

      // No workstream assignment: sees every workstream in their warehouse.
      assert.ok((await mgr.get('/categories')).json.some((c) => c.id === otherCat.id));

      await api.post(`/workstreams/${fx.workstream.id}/managers`, { userId: user.id });
      const visible = (await mgr.get('/categories')).json;
      assert.ok(visible.every((c) => c.workstreamId === fx.workstream.id), 'scoped list must only contain assigned workstream');
      assert.equal((await mgr.get(`/categories/${otherCat.id}`)).status, 403);
      assert.equal((await mgr.post('/categories', { name: 'nope', workstreamId: otherWs.id })).status, 403);
      assert.equal((await mgr.post('/categories', { name: `mine-${uid()}`, workstreamId: fx.workstream.id })).status, 201);

      await api.delete(`/workstreams/${fx.workstream.id}/managers/${user.id}`);
      assert.ok((await mgr.get('/categories')).json.some((c) => c.id === otherCat.id), 'unassign must lift the scope immediately');
    });
  });

  describe('inventory ledger', () => {
    it('receiving writes a transaction and moves the balance', async () => {
      const res = await api.post('/inventory/receiving', { supplier: 'Acme', productId: fx.product.id, quantity: 100, toLocationId: fx.locA.id, reference: `PO-${run}`, notes: 'first delivery' });
      assert.equal(res.status, 201);
      assert.equal(res.json.type, 'RECEIVE');
      assert.match(res.json.reason, /^Supplier: Acme \| first delivery$/);
      assert.deepEqual(await balanceOf(fx.product.id, fx.locA.id), { onHand: 100, reserved: 0, available: 100 });
    });

    it('rejects a non-positive quantity and more than 3 decimals', async () => {
      const body = { supplier: 'x', productId: fx.product.id, toLocationId: fx.locA.id };
      assert.equal((await api.post('/inventory/receiving', { ...body, quantity: 0 })).status, 400);
      assert.equal((await api.post('/inventory/receiving', { ...body, quantity: 1.2345 })).status, 400);
    });

    it('stock only lives at leaf locations', async () => {
      const parent = (await api.post('/locations', { warehouseId: fx.warehouseId, name: 'Parent', code: `P-${uid()}`, locationType: 'ZONE' })).json;
      await api.post(`/locations/${parent.id}/children`, { name: 'Child', code: `C-${uid()}`, locationType: 'BIN' });
      const res = await api.post('/inventory/receiving', { supplier: 'x', productId: fx.product.id, quantity: 1, toLocationId: parent.id });
      assert.equal(res.status, 400);
      assert.match(res.json.message, /not a leaf location/);
    });

    it('transfers move both legs atomically', async () => {
      const res = await api.post('/inventory/transfers', { productId: fx.product.id, quantity: 30, fromLocationId: fx.locA.id, toLocationId: fx.locB.id, reason: 'rebalance' });
      assert.equal(res.status, 201);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).onHand, 70);
      assert.equal((await balanceOf(fx.product.id, fx.locB.id)).onHand, 30);
    });

    it('cannot take a bucket below zero — clean 409, nothing written', async () => {
      const txnsBefore = (await api.get(`/inventory/transactions?productId=${fx.product.id}`)).json.length;
      const res = await api.post('/inventory/transfers', { productId: fx.product.id, quantity: 9999, fromLocationId: fx.locA.id, toLocationId: fx.locB.id });
      assert.equal(res.status, 409);
      assert.match(res.json.message, /below zero/);
      assert.ok(!/inventory_balances_on_hand_nonneg|SQLSTATE/i.test(res.body), 'no raw DB error may leak');
      assert.equal((await api.get(`/inventory/transactions?productId=${fx.product.id}`)).json.length, txnsBefore);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).onHand, 70);
    });

    it('a transfer needs two different locations', async () => {
      const res = await api.post('/inventory/transfers', { productId: fx.product.id, quantity: 1, fromLocationId: fx.locA.id, toLocationId: fx.locA.id });
      assert.equal(res.status, 400);
    });

    it('the DB trigger blocks any write to inventory_balances outside applyTransaction (rule 2)', async () => {
      await assert.rejects(app.db.exec('UPDATE inventory_balances SET on_hand = 5 WHERE product_id = ?', [fx.product.id]));
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).onHand, 70);
    });

    it('ledger invariant: balances equal the sum of the transactions', async () => {
      const txns = (await api.get(`/inventory/transactions?productId=${fx.product.id}`)).json;
      const net = new Map();
      const add = (id, n) => id && net.set(id, (net.get(id) ?? 0) + n);
      for (const t of txns) {
        const q = Number(t.quantity);
        if (['RECEIVE', 'RETURN'].includes(t.type)) add(t.toLocationId, q);
        else if (['ISSUE', 'SALE', 'DAMAGED', 'LOST'].includes(t.type)) add(t.fromLocationId, -q);
        else if (t.type === 'TRANSFER') (add(t.fromLocationId, -q), add(t.toLocationId, q));
        else if (t.type === 'ADJUSTMENT') (t.toLocationId ? add(t.toLocationId, q) : add(t.fromLocationId, -q));
      }
      const balances = (await api.get(`/inventory/balances?productId=${fx.product.id}`)).json;
      for (const b of balances) assert.equal(Number(b.onHand), net.get(b.locationId) ?? 0, `location ${b.locationId}`);
    });

    it('product totalOnHand and the dashboard update right after a ledger write (stock cache tag)', async () => {
      const list = async () => (await api.get('/products')).json.find((p) => p.id === fx.product.id).totalOnHand;
      const dash = async () => (await api.get('/dashboard')).json.valuation.total;
      const totalBefore = await list();
      const valueBefore = await dash();

      await api.post('/inventory/receiving', { supplier: 'x', productId: fx.product.id, quantity: 10, toLocationId: fx.locA.id });

      assert.equal(await list(), totalBefore + 10);
      assert.equal(await dash(), valueBefore + 10 * 4); // cost price is 4
    });
  });

  describe('two-step adjustments (separation of duties)', () => {
    let requester;
    let requesterId;

    before(async () => {
      const perms = (await api.get('/permissions')).json;
      const role = (await api.post('/roles', { name: `WH-${uid()}` })).json;
      await api.put(`/roles/${role.id}/permissions`, { permissionIds: perms.filter((p) => ['inventory.view', 'inventory.adjust.request', 'inventory.count'].includes(p.key)).map((p) => p.id) });
      const email = `wh-${uid()}@test.local`;
      requesterId = (await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'Floor Staff', roleIds: [role.id] })).json.id;
      await api.put(`/users/${requesterId}/warehouses`, { warehouseIds: [fx.warehouseId] }); // access is deny-by-default
      requester = client(app, { token: (await loginAs(app, { email, password: 'Passw0rd!x' })).accessToken });
    });

    it('a request never moves stock', async () => {
      const before = await balanceOf(fx.product.id, fx.locB.id);
      const res = await requester.post('/inventory/adjustments', { productId: fx.product.id, locationId: fx.locB.id, bucket: 'ON_HAND', delta: 5, direction: 'DECREASE', reason: 'damaged in aisle' });
      assert.equal(res.status, 201);
      assert.equal(res.json.status, 'PENDING');
      fx.adjustmentId = res.json.id;
      assert.deepEqual(await balanceOf(fx.product.id, fx.locB.id), before);
    });

    it('the requester cannot approve (no permission)', async () => {
      assert.equal((await requester.post(`/inventory/adjustments/${fx.adjustmentId}/approve`, {})).status, 403);
    });

    it('nobody can approve their OWN request, even with the permission', async () => {
      const own = (await api.post('/inventory/adjustments', { productId: fx.product.id, locationId: fx.locB.id, bucket: 'ON_HAND', delta: 1, direction: 'INCREASE', reason: 'mine' })).json;
      const res = await api.post(`/inventory/adjustments/${own.id}/approve`, {});
      assert.equal(res.status, 403);
      assert.match(res.json.message, /cannot approve your own/);
    });

    it('a different user approving moves the stock and links the ledger row', async () => {
      const before = (await balanceOf(fx.product.id, fx.locB.id)).onHand;
      const res = await api.post(`/inventory/adjustments/${fx.adjustmentId}/approve`, { reviewNote: 'confirmed' });
      assert.equal(res.status, 201);
      assert.equal(res.json.status, 'APPROVED');
      assert.ok(res.json.transactionId);
      assert.equal((await balanceOf(fx.product.id, fx.locB.id)).onHand, before - 5);
    });

    it('cannot approve twice', async () => {
      assert.equal((await api.post(`/inventory/adjustments/${fx.adjustmentId}/approve`, {})).status, 409);
    });

    it('rejecting needs a note and moves no stock', async () => {
      const req = (await requester.post('/inventory/adjustments', { productId: fx.product.id, locationId: fx.locB.id, bucket: 'ON_HAND', delta: 2, direction: 'DECREASE', reason: 'lost?' })).json;
      const before = (await balanceOf(fx.product.id, fx.locB.id)).onHand;
      assert.equal((await api.post(`/inventory/adjustments/${req.id}/reject`, {})).status, 400);
      const res = await api.post(`/inventory/adjustments/${req.id}/reject`, { reviewNote: 'found it' });
      assert.equal(res.json.status, 'REJECTED');
      assert.equal((await balanceOf(fx.product.id, fx.locB.id)).onHand, before);
    });

    it('a photo can ride along as multipart, and is served back with an ETag', async () => {
      const body = await multipart(
        { productId: fx.product.id, locationId: fx.locB.id, bucket: 'DAMAGED', delta: 1, direction: 'INCREASE', reason: 'photo evidence' },
        [{ field: 'photo', content: PNG, type: 'image/png', filename: 'evidence.png' }],
      );
      const created = await requester.request('POST', '/inventory/adjustments', { raw: body });
      assert.equal(created.status, 201, created.body);
      assert.ok(created.json.photoPath);

      const photo = await api.get(`/inventory/adjustments/${created.json.id}/photo`);
      assert.equal(photo.status, 200);
      assert.equal(photo.headers['content-type'], 'image/png');
      assert.ok(photo.headers.etag);
      const cached = await api.get(`/inventory/adjustments/${created.json.id}/photo`, { headers: { 'if-none-match': photo.headers.etag } });
      assert.equal(cached.status, 304);
    });

    it('multipart fields are validated like JSON (delta "5" coerces, bad enum is 400, no orphaned upload)', async () => {
      const bad = await multipart(
        { productId: fx.product.id, locationId: fx.locB.id, bucket: 'NOT_A_BUCKET', delta: 1, direction: 'INCREASE', reason: 'x' },
        [{ field: 'photo', content: PNG, type: 'image/png', filename: 'p.png' }],
      );
      assert.equal((await requester.request('POST', '/inventory/adjustments', { raw: bad })).status, 400);
    });

    it('JSON creates still work (no photo)', async () => {
      const res = await requester.post('/inventory/adjustments', { productId: fx.product.id, locationId: fx.locB.id, bucket: 'ON_HAND', delta: 1, direction: 'INCREASE', reason: 'json' });
      assert.equal(res.status, 201);
      assert.equal(res.json.photoPath, null);
    });

    it('a non-image photo is rejected', async () => {
      const body = await multipart(
        { productId: fx.product.id, locationId: fx.locB.id, bucket: 'ON_HAND', delta: 1, direction: 'INCREASE', reason: 'x' },
        [{ field: 'photo', content: Buffer.from('not an image'), type: 'text/plain', filename: 'x.txt' }],
      );
      const res = await requester.request('POST', '/inventory/adjustments', { raw: body });
      assert.equal(res.status, 400);
      assert.match(res.json.message, /Photo must be a JPEG, PNG, or WebP/);
    });

    it('a stock count records variance and raises PENDING adjustments — it never writes the ledger', async () => {
      const expected = (await balanceOf(fx.product.id, fx.locA.id)).onHand;
      const txnsBefore = (await api.get(`/inventory/transactions?productId=${fx.product.id}`)).json.length;

      const count = await requester.post('/inventory/counts', { locationId: fx.locA.id, productIds: [fx.product.id] });
      assert.equal(count.status, 201);
      assert.equal(Number(count.json.items[0].expectedQty), expected);

      const submitted = await requester.patch(`/inventory/counts/${count.json.id}`, { items: [{ productId: fx.product.id, countedQty: expected - 3 }] });
      assert.equal(submitted.status, 200);
      assert.equal(submitted.json.status, 'SUBMITTED');
      assert.equal(submitted.json.createdAdjustmentIds.length, 1);
      assert.equal(Number(submitted.json.items[0].difference), -3);

      assert.equal((await api.get(`/inventory/transactions?productId=${fx.product.id}`)).json.length, txnsBefore);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).onHand, expected);

      const again = await requester.patch(`/inventory/counts/${count.json.id}`, { items: [{ productId: fx.product.id, countedQty: expected }] });
      assert.equal(again.status, 409);
    });

    it('a count must cover exactly the snapshotted products', async () => {
      const count = (await requester.post('/inventory/counts', { locationId: fx.locA.id, productIds: [fx.product.id] })).json;
      const res = await requester.patch(`/inventory/counts/${count.id}`, { items: [{ productId: '00000000-0000-4000-8000-000000000000', countedQty: 1 }] });
      assert.equal(res.status, 400);
      assert.match(res.json.message, /must exactly match/);
    });
  });

  describe('external API (API-key authenticated)', () => {
    let key; // { id, rawKey }
    let ext;

    before(async () => {
      key = (await api.post('/api-keys', { name: `test-${uid()}`, scopes: ['catalogue:read', 'stock:read', 'stock:reserve', 'stock:issue', 'locations:read'] })).json;
      ext = client(app, { headers: { 'x-api-key': key.rawKey } });
    });

    it('returns the raw key once, never the hash, and never on list', async () => {
      assert.match(key.rawKey, /^whk_/);
      assert.equal(key.keyHash, undefined);
      const listed = (await api.get('/api-keys')).json.find((k) => k.id === key.id);
      assert.equal(listed.rawKey, undefined);
      assert.equal(listed.keyHash, undefined);
    });

    it('rejects a missing, unknown, or unscoped key', async () => {
      assert.equal((await client(app).get('/api/v1/catalogue')).status, 401);
      assert.equal((await client(app).get('/api/v1/catalogue', { apiKey: 'whk_nope' })).status, 401);

      const narrow = (await api.post('/api-keys', { name: `narrow-${uid()}`, scopes: ['catalogue:read'] })).json;
      const res = await client(app).post('/api/v1/stock/reserve', { reference: 'x', lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 1 }] }, { apiKey: narrow.rawKey });
      assert.equal(res.status, 403);
      assert.equal(res.json.message, 'API key lacks the required scope');
    });

    it('a user JWT is not an API key', async () => {
      assert.equal((await api.get('/api/v1/catalogue')).status, 401);
    });

    it('serves the catalogue with workstream + attributes, and the locations list', async () => {
      const cat = await ext.get('/api/v1/catalogue');
      assert.equal(cat.status, 200);
      assert.ok(cat.json.products.some((p) => p.id === fx.product.id));
      assert.ok(cat.json.categories.every((c) => c.workstream));
      const loc = await ext.get('/api/v1/locations');
      assert.equal(loc.status, 200);
      assert.ok(loc.json.locations.some((l) => l.id === fx.locA.id));
    });

    it('availability = on_hand - reserved', async () => {
      const res = await ext.post('/api/v1/stock/availability', { items: [{ productId: fx.product.id, locationId: fx.locA.id }, { productId: fx.product.id }] });
      assert.equal(res.status, 200);
      const a = (await balanceOf(fx.product.id, fx.locA.id)).available;
      assert.equal(res.json.items[0].available, a);
    });

    it('allocation options: every location with available stock, and the age of its oldest stock', async () => {
      const created = await api.post('/products', {
        sku: `FIFO-${run}`,
        name: `Fifo ${run}`,
        categoryId: fx.category.id,
        sellingPrice: 1,
        costPrice: 1,
        uom: 'EACH',
      });
      assert.equal(created.status, 201, created.body);
      const product = created.json;
      const receive = async (locationId, quantity) => {
        const r = await api.post('/inventory/receiving', { supplier: 'Acme', productId: product.id, quantity, toLocationId: locationId, reference: `FIFO-${run}` });
        assert.equal(r.status, 201, r.body);
      };
      await receive(fx.locB.id, 4); // older stock in B
      await new Promise((r) => setTimeout(r, 20));
      await receive(fx.locA.id, 6); // newer stock in A
      await new Promise((r) => setTimeout(r, 20));
      await receive(fx.locB.id, 2); // B topped up: B still holds its older units too

      const res = await ext.post('/api/v1/stock/allocation-options', { productIds: [product.id] });
      assert.equal(res.status, 200);
      const [entry] = res.json.products;
      const byLoc = new Map(entry.locations.map((l) => [l.locationId, l]));
      assert.equal(byLoc.get(fx.locA.id).available, 6);
      assert.equal(byLoc.get(fx.locB.id).available, 6);
      assert.equal(byLoc.get(fx.locB.id).warehouseId, fx.warehouseId);
      assert.ok(
        new Date(byLoc.get(fx.locB.id).oldestStockAt) < new Date(byLoc.get(fx.locA.id).oldestStockAt),
        "B's oldest units arrived before A's",
      );

      // Reserved stock is not available; a location with nothing available is not listed.
      await ext.post('/api/v1/stock/reserve', { reference: `FIFO-${run}`, lines: [{ productId: product.id, locationId: fx.locA.id, quantity: 6 }] });
      const after = (await ext.post('/api/v1/stock/allocation-options', { productIds: [product.id] })).json.products[0];
      assert.deepEqual(after.locations.map((l) => l.locationId), [fx.locB.id]);
      await ext.post('/api/v1/stock/release', { reference: `FIFO-${run}` });
    });

    it('a shortfall is HTTP 200 with success:false and structured shortLines', async () => {
      const res = await ext.post('/api/v1/stock/reserve', { reference: `SHORT-${run}`, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 100000 }] });
      assert.equal(res.status, 200);
      assert.equal(res.json.success, false);
      assert.equal(res.json.shortLines.length, 1);
      assert.equal(res.json.shortLines[0].requested, 100000);
    });

    it('reserve -> replay is idempotent -> release -> release again', async () => {
      const ref = `RES-${run}`;
      const availableBefore = (await balanceOf(fx.product.id, fx.locA.id)).available;
      const lines = [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 5 }];

      const first = await ext.post('/api/v1/stock/reserve', { reference: ref, lines });
      assert.equal(first.status, 200);
      assert.equal(first.json.success, true);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).available, availableBefore - 5);

      const replay = await ext.post('/api/v1/stock/reserve', { reference: ref, lines });
      assert.equal(replay.json.success, true);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).available, availableBefore - 5, 'replay must not double-reserve');

      const released = await ext.post('/api/v1/stock/release', { reference: ref });
      assert.equal(released.json.alreadyReleased, false);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).available, availableBefore);

      const again = await ext.post('/api/v1/stock/release', { reference: ref });
      assert.equal(again.json.alreadyReleased, true);
      assert.equal((await ext.post('/api/v1/stock/release', { reference: `UNKNOWN-${run}` })).json.alreadyReleased, false);
    });

    it('issue: partial dispatch releases the remainder; replay is idempotent; after release it 409s', async () => {
      const ref = `ISS-${run}`;
      const before = await balanceOf(fx.product.id, fx.locA.id);
      await ext.post('/api/v1/stock/reserve', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 5 }] });

      const issued = await ext.post('/api/v1/stock/issue', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 3 }] });
      assert.equal(issued.status, 200);
      assert.equal(issued.json.alreadyIssued, false);
      assert.deepEqual(issued.json.issued[0], { productId: fx.product.id, locationId: fx.locA.id, reserved: 5, issued: 3 });

      const after = await balanceOf(fx.product.id, fx.locA.id);
      assert.equal(after.onHand, before.onHand - 3);
      assert.equal(after.reserved, before.reserved, 'the whole reservation is cleared, the shortfall becomes available again');

      assert.equal((await ext.post('/api/v1/stock/issue', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 3 }] })).json.alreadyIssued, true);
      assert.equal((await balanceOf(fx.product.id, fx.locA.id)).onHand, before.onHand - 3, 'replay must not issue twice');

      assert.equal((await ext.post('/api/v1/stock/issue', { reference: `NOPE-${run}`, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 1 }] })).status, 404);

      const relRef = `REL-${run}`;
      await ext.post('/api/v1/stock/reserve', { reference: relRef, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 1 }] });
      await ext.post('/api/v1/stock/release', { reference: relRef });
      assert.equal((await ext.post('/api/v1/stock/issue', { reference: relRef, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 1 }] })).status, 409);
    });

    it('cannot issue more than was reserved', async () => {
      const ref = `OVER-${run}`;
      await ext.post('/api/v1/stock/reserve', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 2 }] });
      const res = await ext.post('/api/v1/stock/issue', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 3 }] });
      assert.equal(res.status, 400);
      await ext.post('/api/v1/stock/release', { reference: ref });
    });

    it('ledger rows from API calls are attributed to the system user, and audit records the key', async () => {
      const ref = `AUD-${run}`;
      await ext.post('/api/v1/stock/reserve', { reference: ref, lines: [{ productId: fx.product.id, locationId: fx.locA.id, quantity: 1 }] });
      await settle();
      const audit = (await api.get(`/audit-logs?entity=stock_reservations&entityId=${ref}`)).json;
      assert.equal(audit.total, 1);
      assert.equal(audit.data[0].apiKey.id, key.id);
      assert.equal(audit.data[0].user, null);
      assert.equal(audit.data[0].action, 'RESERVE');

      const txns = (await api.get(`/inventory/transactions?productId=${fx.product.id}&type=RESERVATION`)).json;
      const mine = txns.find((t) => t.reference === ref);
      assert.ok(mine);
      await ext.post('/api/v1/stock/release', { reference: ref });
    });

    it('revoking a key takes effect on the very next request (verified-key cache is invalidated)', async () => {
      const fresh = (await api.post('/api-keys', { name: `revoke-${uid()}`, scopes: ['catalogue:read'] })).json;
      assert.equal((await client(app).get('/api/v1/catalogue', { apiKey: fresh.rawKey })).status, 200); // primes the cache
      assert.equal((await client(app).get('/api/v1/catalogue', { apiKey: fresh.rawKey })).status, 200);
      await api.post(`/api-keys/${fresh.id}/revoke`, {});
      assert.equal((await client(app).get('/api/v1/catalogue', { apiKey: fresh.rawKey })).status, 401);
    });
  });

  describe('uploads', () => {
    it('product image: upload, serve with ETag/304, reject bad type, delete', async () => {
      const good = await multipart({ isPrimary: 'true', sortOrder: 2 }, [{ field: 'file', content: PNG, type: 'image/png', filename: 'a.png' }]);
      const created = await api.request('POST', `/products/${fx.product.id}/images/upload`, { raw: good });
      assert.equal(created.status, 201, created.body);
      assert.ok(created.json.storagePath);
      assert.equal(created.json.isPrimary, true);
      assert.equal(created.json.sortOrder, 2);

      const file = await api.get(`/products/${fx.product.id}/images/${created.json.id}/file`);
      assert.equal(file.status, 200);
      assert.equal(file.headers['content-type'], 'image/png');
      assert.deepEqual(Buffer.from(file.rawBuffer), PNG);
      assert.equal((await api.get(`/products/${fx.product.id}/images/${created.json.id}/file`, { headers: { 'if-none-match': file.headers.etag } })).status, 304);

      // The product read (cached) must now include the image.
      assert.ok((await api.get(`/products/${fx.product.id}`)).json.images.some((i) => i.id === created.json.id));

      const bad = await multipart({}, [{ field: 'file', content: Buffer.from('<script>'), type: 'text/html', filename: 'x.html' }]);
      assert.equal((await api.request('POST', `/products/${fx.product.id}/images/upload`, { raw: bad })).status, 400);
      const none = await multipart({ sortOrder: 1 }, []);
      assert.equal((await api.request('POST', `/products/${fx.product.id}/images/upload`, { raw: none })).status, 400);

      assert.equal((await api.delete(`/products/${fx.product.id}/images/${created.json.id}`)).json.deleted, true);
      assert.equal((await api.get(`/products/${fx.product.id}/images/${created.json.id}/file`)).status, 404);
      assert.ok(!(await api.get(`/products/${fx.product.id}`)).json.images.some((i) => i.id === created.json.id));
    });

    it('a URL image and only one primary at a time', async () => {
      const a = (await api.post(`/products/${fx.product.id}/images`, { url: 'https://cdn.example.com/a.jpg', isPrimary: true })).json;
      const b = (await api.post(`/products/${fx.product.id}/images`, { url: 'https://cdn.example.com/b.jpg', isPrimary: true })).json;
      const list = (await api.get(`/products/${fx.product.id}/images`)).json;
      assert.equal(list.filter((i) => i.isPrimary).length, 1);
      assert.equal(list.find((i) => i.isPrimary).id, b.id);
      assert.equal((await api.get(`/products/${fx.product.id}/images/${a.id}/file`)).status, 404, 'URL images have no file');
    });

    it('workstream image upload and removal', async () => {
      const body = await multipart({}, [{ field: 'file', content: PNG, type: 'image/png', filename: 'w.png' }]);
      const up = await api.request('POST', `/workstreams/${fx.workstream.id}/image/upload`, { raw: body });
      assert.equal(up.status, 201);
      assert.ok(up.json.imagePath);
      assert.equal((await api.get(`/workstreams/${fx.workstream.id}/image/file`)).status, 200);
      await api.delete(`/workstreams/${fx.workstream.id}/image`);
      assert.equal((await api.get(`/workstreams/${fx.workstream.id}/image/file`)).status, 404);
    });
  });

  describe('product import', () => {
    async function workbook(rows) {
      const wb = new ExcelJS.Workbook();
      const ws = wb.addWorksheet('Products');
      ws.addRow(['sku', 'name', 'workstream_code', 'category_name', 'selling_price', 'cost_price', 'uom']);
      for (const r of rows) ws.addRow(r);
      return Buffer.from(await wb.xlsx.writeBuffer());
    }
    const xlsx = (content) => multipart({}, [{ field: 'file', content, type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', filename: 'products.xlsx' }]);

    it('downloads a template', async () => {
      const res = await api.get('/products/import/template');
      assert.equal(res.status, 200);
      assert.match(res.headers['content-type'], /spreadsheetml/);
      assert.match(res.headers['content-disposition'], /product-import-template\.xlsx/);
      assert.ok(res.rawBuffer.length > 1000);
    });

    it('preview stages, confirm writes; rows are validated strictly; the session is single-use', async () => {
      const goodSku = `IMP-${uid()}`;
      const file = await workbook([
        [goodSku, 'Imported Item', fx.workstream.code, fx.category.name, 12.5, 6, 'EACH'],
        [`BAD-${uid()}`, 'Bad price', fx.workstream.code, fx.category.name, 'R12,50', '', 'EACH'],
        [`BAD-${uid()}`, 'Bad workstream', 'NO-SUCH-WS', fx.category.name, 5, '', 'EACH'],
      ]);
      const preview = await api.request('POST', '/products/import/preview', { raw: await xlsx(file) });
      assert.equal(preview.status, 201, preview.body);
      assert.deepEqual(preview.json.summary, { createCount: 1, updateCount: 0, rejectCount: 2, totalRows: 3 });
      assert.match(preview.json.rejected[0].reason, /selling_price/);

      // Nothing is written by a preview.
      assert.ok(!(await api.get('/products?search=' + goodSku)).json.length);

      const confirm = await api.post('/products/import/confirm', { importSessionId: preview.json.importSessionId });
      assert.equal(confirm.status, 201);
      assert.equal(confirm.json.created, 1);
      assert.equal(confirm.json.failed.length, 0);
      assert.ok((await api.get('/products?search=' + goodSku)).json.length === 1);

      assert.equal((await api.post('/products/import/confirm', { importSessionId: preview.json.importSessionId })).status, 404);
    });

    it('re-importing an existing SKU is an update with a change list', async () => {
      const file = await workbook([[fx.product.sku, fx.product.name, fx.workstream.code, fx.category.name, 11, 4, 'EACH']]);
      const preview = await api.request('POST', '/products/import/preview', { raw: await xlsx(file) });
      assert.equal(preview.json.summary.updateCount, 1);
      assert.ok(preview.json.toUpdate[0].changes.some((c) => c.field === 'sellingPrice'));
    });

    it('rejects a non-spreadsheet upload', async () => {
      const body = await multipart({}, [{ field: 'file', content: Buffer.from('hello'), type: 'text/plain', filename: 'notes.txt' }]);
      const res = await api.request('POST', '/products/import/preview', { raw: body });
      assert.equal(res.status, 400);
      assert.match(res.json.message, /Unsupported file type/);
    });
  });

  describe('audit log', () => {
    it('records who did what, redacts secrets, and skips reads', async () => {
      const email = `aud-${uid()}@test.local`;
      const user = (await api.post('/users', { email, password: 'Secr3tPass!', fullName: 'Audit Me' })).json;
      await settle();

      const rows = (await api.get(`/audit-logs?entity=users&entityId=${user.id}`)).json;
      const row = rows.data.find((r) => r.action === 'CREATE');
      assert.ok(row, 'create must be audited');
      assert.equal(row.user.email, 'admin@test.local');
      assert.equal(row.newValue.password, '[REDACTED]');
      assert.equal(row.newValue.email, email);

      const totalBefore = (await api.get('/audit-logs')).json.total;
      await api.get('/products');
      await api.get('/dashboard');
      await settle();
      assert.equal((await api.get('/audit-logs')).json.total, totalBefore, 'GETs must not write audit rows');
    });

    it('does not audit failed requests', async () => {
      const totalBefore = (await api.get('/audit-logs')).json.total;
      await api.post('/warehouses', { name: 'x' }); // 400
      await settle();
      assert.equal((await api.get('/audit-logs')).json.total, totalBefore);
    });

    it('login is audited as LOGIN with the user id', async () => {
      await loginAs(app);
      await settle();
      const rows = (await api.get('/audit-logs?entity=auth&action=LOGIN&pageSize=1')).json;
      assert.equal(rows.data[0].action, 'LOGIN');
      assert.ok(rows.data[0].entityId);
      assert.equal(rows.data[0].newValue.password, '[REDACTED]');
    });
  });

  describe('location tree', () => {
    it('is an unbounded self-referencing tree with subtree reads, moves and cycle protection', async () => {
      const root = (await api.post('/locations', { warehouseId: fx.warehouseId, name: 'Zone', code: `Z-${uid()}`, locationType: 'ZONE' })).json;
      let parent = root;
      const chain = [root];
      for (let depth = 0; depth < 6; depth++) {
        parent = (await api.post(`/locations/${parent.id}/children`, { name: `L${depth}`, code: `D${depth}-${uid()}`, locationType: 'LEVEL' })).json;
        chain.push(parent);
      }
      const subtree = (await api.get(`/locations/${root.id}/subtree`)).json;
      assert.equal(subtree.length, 7);
      assert.deepEqual(subtree.map((l) => l.depth), [0, 1, 2, 3, 4, 5, 6]);
      assert.equal(typeof subtree[0].isActive, 'boolean');

      const cycle = await api.post(`/locations/${root.id}/move`, { parentId: chain[6].id });
      assert.equal(cycle.status, 409);
      const toRoot = await api.post(`/locations/${chain[3].id}/move`, { parentId: null });
      assert.equal(toRoot.json.parentId, null);
      assert.equal((await api.get(`/locations/${root.id}/subtree`)).json.length, 3, 'subtree cache must reflect the move');
      assert.equal((await api.post(`/locations/${root.id}/move`, {})).status, 400, 'parentId key is required');
    });

    it('generates N levels under a parent', async () => {
      const rack = (await api.post('/locations', { warehouseId: fx.warehouseId, name: 'Rack', code: `RK-${uid()}`, locationType: 'RACK' })).json;
      const res = await api.post(`/locations/${rack.id}/levels`, { count: 12, locationType: 'SHELF', namePrefix: 'Shelf' });
      assert.equal(res.status, 201);
      assert.equal(res.json.length, 12);
      assert.equal(res.json[0].code, `${rack.code}-S1`);
    });

    it('carries an optional capacity (fill/utilisation), set on create, levels and edit, cleared with null', async () => {
      const rack = (await api.post('/locations', { warehouseId: fx.warehouseId, name: 'Cap rack', code: `CR-${uid()}`, locationType: 'RACK' })).json;
      assert.equal(rack.capacity, null);
      const levels = (await api.post(`/locations/${rack.id}/levels`, { count: 2, capacity: 400 })).json;
      assert.deepEqual(levels.map((l) => l.capacity), [400, 400]);
      const slot = (await api.post(`/locations/${rack.id}/children`, { name: 'Bin', code: `CB-${uid()}`, locationType: 'BIN', capacity: 120 })).json;
      assert.equal(slot.capacity, 120);
      assert.equal((await api.patch(`/locations/${slot.id}`, { capacity: 150 })).json.capacity, 150);
      assert.equal((await api.patch(`/locations/${slot.id}`, { name: 'Bin renamed' })).json.capacity, 150, 'untouched when omitted');
      assert.equal((await api.patch(`/locations/${slot.id}`, { capacity: null })).json.capacity, null);
      assert.equal((await api.patch(`/locations/${slot.id}`, { capacity: -1 })).status, 400);
      const subtree = (await api.get(`/locations/${rack.id}/subtree`)).json;
      assert.ok(subtree.some((l) => l.capacity === 400), 'the tree read carries capacity too');
    });
  });

  describe('list summaries for the console', () => {
    it('lists each workstream with its scoped managers', async () => {
      const ws = (await api.post('/workstreams', { warehouseId: fx.warehouseId, name: `Mgd ${uid()}`, code: `M-${uid()}` })).json;
      const user = (await api.post('/users', { email: `m-${uid()}@test.local`, password: 'Passw0rd!x', fullName: 'Listed Manager', roleIds: [] })).json;
      await api.put(`/users/${user.id}/warehouses`, { warehouseIds: [fx.warehouseId] });
      assert.equal((await api.post(`/workstreams/${ws.id}/managers`, { userId: user.id })).status, 201);
      const listed = (await api.get('/workstreams')).json.find((w) => w.id === ws.id);
      assert.deepEqual(listed.managers, [{ userId: user.id, fullName: 'Listed Manager' }]);
      assert.deepEqual((await api.get('/workstreams')).json.find((w) => w.id === fx.workstream.id).managers, []);
    });

    it('lists each warehouse with location, slot, capacity, unit and workstream totals', async () => {
      const wh = (await api.post('/warehouses', { name: `Sum ${uid()}`, code: `S-${uid()}` })).json;
      const zone = (await api.post('/locations', { warehouseId: wh.id, name: 'Zone', code: `SZ-${uid()}`, locationType: 'ZONE' })).json;
      const bins = (await api.post(`/locations/${zone.id}/levels`, { count: 2, locationType: 'BIN', capacity: 50 })).json;
      await api.post('/workstreams', { warehouseId: wh.id, name: `SW ${uid()}`, code: `SW-${uid()}` });
      assert.equal((await api.post('/inventory/receiving', { productId: fx.product.id, toLocationId: bins[0].id, quantity: 7, supplier: 'Test supplier' })).status, 201);
      const listed = (await api.get('/warehouses')).json.find((w) => w.id === wh.id);
      assert.deepEqual(listed.summary, { locations: 3, slots: 2, capacity: 100, units: 7, workstreams: 1 });
    });
  });

  describe('report branding', () => {
    it('anyone reads it, even signed out (sign-in page, favicon); only settings.manage changes it', async () => {
      const initial = (await api.get('/settings/branding')).json;
      assert.equal(typeof initial.companyName, 'string');
      const anonymous = client(app);
      assert.equal((await anonymous.get('/settings/branding')).status, 200);
      assert.equal((await anonymous.put('/settings/branding', { companyName: 'Hijack' })).status, 401);

      const renamed = await api.put('/settings/branding', { companyName: `  Acme Wholesale ${run}  ` });
      assert.equal(renamed.status, 200, renamed.body);
      assert.equal(renamed.json.companyName, `Acme Wholesale ${run}`);

      const logo = await multipart({}, [{ field: 'file', content: PNG, type: 'image/png', filename: 'logo.png' }]);
      const uploaded = await api.request('POST', '/settings/branding/logo', { raw: logo });
      assert.equal(uploaded.status, 200, uploaded.body);
      assert.equal(uploaded.json.hasLogo, true);
      const file = await client(app).get('/settings/branding/logo'); // no sign-in needed
      assert.equal(file.status, 200);
      assert.equal(file.headers['content-type'], 'image/png');

      const notImage = await multipart({}, [{ field: 'file', content: Buffer.from('hello'), type: 'text/plain', filename: 'x.txt' }]);
      assert.equal((await api.request('POST', '/settings/branding/logo', { raw: notImage })).status, 400);

      const reset = await api.delete('/settings/branding/logo');
      assert.equal(reset.json.hasLogo, false);
      assert.equal((await api.get('/settings/branding/logo')).status, 404);
      await api.put('/settings/branding', { companyName: initial.companyName });
    });
  });

  describe('platform concerns', () => {
    it('sends CORS headers only to allowed origins', async () => {
      const allowed = await app.inject({ method: 'GET', url: '/health', headers: { origin: 'http://localhost:8090' } });
      assert.equal(allowed.headers['access-control-allow-origin'], 'http://localhost:8090');
      assert.equal(allowed.headers['access-control-allow-credentials'], 'true');
      const denied = await app.inject({ method: 'GET', url: '/health', headers: { origin: 'https://evil.example' } });
      assert.equal(denied.headers['access-control-allow-origin'], undefined);
    });

    it('compresses large JSON responses', async () => {
      const { accessToken } = await loginAs(app);
      const res = await app.inject({ method: 'GET', url: '/products', headers: { authorization: `Bearer ${accessToken}`, 'accept-encoding': 'gzip' } });
      assert.equal(res.headers['content-encoding'], 'gzip');
    });

    it('an oversized JSON body is a 413, not a misleading "file" error', async () => {
      const res = await api.request('POST', '/warehouses', { raw: { payload: JSON.stringify({ name: 'x'.repeat(2 * 1024 * 1024), code: 'y' }), contentType: 'application/json' } });
      assert.equal(res.status, 413);
      assert.ok(!/file/i.test(res.json.message));
    });

    it('rejects a token signed with a different algorithm', async () => {
      const jwt = require('jsonwebtoken');
      const forged = jwt.sign({ sub: 'x', email: 'x' }, 'test-access-secret', { algorithm: 'HS512' });
      assert.equal((await client(app).get('/products', { token: forged })).status, 401);
      const none = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url') + '.' + Buffer.from(JSON.stringify({ sub: 'x' })).toString('base64url') + '.';
      assert.equal((await client(app).get('/products', { token: none })).status, 401);
    });

    it('sets security headers', async () => {
      const res = await app.inject({ method: 'GET', url: '/health' });
      assert.equal(res.headers['x-content-type-options'], 'nosniff');
      assert.ok(res.headers['content-security-policy']);
    });

    it('serves under an API base path when API_BASE_PATH is set, auditing the real entity', async () => {
      const prefixed = await createTestApp({ basePath: 'api' });
      try {
        assert.equal((await prefixed.inject({ method: 'GET', url: '/api/health' })).statusCode, 200);
        assert.equal((await prefixed.inject({ method: 'GET', url: '/health' })).statusCode, 404);
        const login = await prefixed.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'admin@test.local', password: 'TestPass123!' } });
        assert.equal(login.statusCode, 200);
        const c = client(prefixed, { token: login.json().accessToken });
        const w = await c.post('/api/warehouses', { name: `Pref ${uid()}`, code: `PF-${uid()}` });
        assert.equal(w.status, 201);
        await settle();
        const rows = (await c.get(`/api/audit-logs?entityId=${w.json.id}`)).json;
        assert.equal(rows.data[0].entity, 'warehouses', 'the base path must not become the audit entity');
      } finally {
        await prefixed.close();
      }
    });

    it('cache can be switched off entirely without changing behaviour', async () => {
      const uncached = await createTestApp({ cache: { enabled: false } });
      try {
        const { accessToken } = await loginAsOn(uncached);
        const c = client(uncached, { token: accessToken });
        const a = (await c.get('/products')).json.length;
        const b = (await c.get('/products')).json.length;
        assert.equal(a, b);
        assert.equal(uncached.cache.stats.hits, 0);
      } finally {
        await uncached.close();
      }
    });
  });

  async function loginAsOn(otherApp) {
    return loginAs(otherApp);
  }
});
