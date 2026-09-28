'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createFakeWarehouse, createTestApp, client, loginAs, uid, settle } = require('./helpers');

const SOAP = '11111111-1111-4111-8111-111111111111';
const INACTIVE = '22222222-2222-4222-8222-222222222222';

describe('ordering API (Express port)', () => {
  let warehouse;
  let app;
  let api; // admin
  const fx = {};

  before(async () => {
    warehouse = await createFakeWarehouse();
    app = await createTestApp({ warehouseApi: { url: warehouse.url, key: 'test-key' } });
    api = client(app.origin, (await loginAs(app.origin)).accessToken);
    fx.customer = (await api.post('/customers', { name: `Cust ${uid()}`, phone: '+268 7600 1111' })).json;
    fx.locationId = warehouse.state.locationId;
  });

  after(async () => {
    await app.close();
    await warehouse.close();
  });

  /** A draft with one line of `qty` soap. */
  const newOrder = async (qty = 4) =>
    (await api.post('/orders', { customerId: fx.customer.id, deliveryInfo: 'Gate 2', items: [{ productId: SOAP, quantity: qty }] })).json;

  describe('auth & errors', () => {
    it('logs in; rejects bad passwords with the standard error body', async () => {
      const bad = await client(app.origin).post('/auth/login', { email: 'admin@test.local', password: 'nope' });
      assert.equal(bad.status, 401);
      assert.deepEqual(Object.keys(bad.json).sort(), ['error', 'message', 'path', 'statusCode', 'timestamp']);
    });

    it('guards before validating: no token is 401 even with a bad body', async () => {
      assert.equal((await client(app.origin).post('/orders', { nonsense: true })).status, 401);
    });

    it('rejects unknown properties (forbidNonWhitelisted)', async () => {
      const res = await api.post('/customers', { name: 'X', favouriteColour: 'blue' });
      assert.equal(res.status, 400);
      assert.match(JSON.stringify(res.json.message), /favouriteColour should not exist/);
    });
  });

  describe('orders', () => {
    it('prices every line from the warehouse catalogue — never from the client', async () => {
      const res = await api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 2, unitPrice: 1 }] });
      assert.equal(res.status, 400, 'a client-supplied unitPrice is rejected outright');

      const order = await newOrder(4);
      assert.equal(order.status, 'DRAFT');
      assert.equal(order.items[0].productName, 'Bar Soap');
      assert.equal(order.items[0].unitPrice, '12.5');
      assert.equal(order.items[0].lineTotal, '50');
      assert.equal(order.total, '50');
      assert.match(order.orderNumber, /^ORD-\d{8}-[A-Z0-9]{6}$/);
      assert.equal(order.statusHistory[0].toStatus, 'DRAFT');
      assert.equal(order.statusHistory[0].changedByUser.fullName, 'System Administrator');
    });

    it('refuses an inactive product', async () => {
      const res = await api.post('/orders', { customerId: fx.customer.id, items: [{ productId: INACTIVE, quantity: 1 }] });
      assert.equal(res.status, 400);
      assert.match(res.json.message, /OLD-1 is not active/);
    });

    it('editing a draft replaces its items and recomputes the total', async () => {
      const order = await newOrder(1);
      const res = await api.patch(`/orders/${order.id}`, { items: [{ productId: SOAP, quantity: 3 }] });
      assert.equal(res.json.items.length, 1);
      assert.equal(res.json.total, '37.5');
    });

    it('walks the full lifecycle, with the warehouse doing the stock side', async () => {
      const order = await newOrder(4);
      assert.equal((await api.post(`/orders/${order.id}/submit`)).json.status, 'PENDING_APPROVAL');
      assert.equal((await api.post(`/orders/${order.id}/approve`, { note: 'ok' })).json.status, 'APPROVED');

      const itemId = order.items[0].id;
      const reserved = await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: itemId, locationId: fx.locationId }] });
      assert.equal(reserved.json.status, 'STOCK_RESERVED', reserved.body);
      assert.equal(reserved.json.items[0].reservedLocationId, fx.locationId);
      const reserveCall = warehouse.state.calls.find((c) => c.path === '/api/v1/stock/reserve' && c.body.reference === order.id);
      assert.equal(reserveCall.key, 'test-key');
      assert.equal(reserveCall.body.label, `${order.orderNumber} · ${fx.customer.name}`, 'packers get a readable label');

      await api.post(`/orders/${order.id}/pick`, { items: [{ orderItemId: itemId, pickedQty: 4 }] });
      const packed = await api.post(`/orders/${order.id}/pack`, { items: [{ orderItemId: itemId, packedQty: 3 }] });
      assert.equal(packed.json.status, 'PACKED');
      await api.post(`/orders/${order.id}/ready`);
      const dispatched = await api.post(`/orders/${order.id}/dispatch`);
      assert.equal(dispatched.json.status, 'PARTIALLY_FULFILLED', 'packed 3 of 4');
      assert.equal(dispatched.json.items[0].quantityFulfilled, '3');
      assert.equal((await api.post(`/orders/${order.id}/deliver`)).json.status, 'DELIVERED');
      const done = await api.post(`/orders/${order.id}/complete`);
      assert.equal(done.json.status, 'COMPLETED');
      assert.equal(done.json.paymentStatus, 'UNPAID', 'payment is a separate lifecycle (rule 6)');
      assert.deepEqual(
        done.json.statusHistory.map((h) => h.toStatus),
        ['DRAFT', 'SUBMITTED', 'PENDING_APPROVAL', 'APPROVED', 'STOCK_RESERVED', 'PICKING', 'PACKED', 'READY_FOR_DISPATCH', 'PARTIALLY_FULFILLED', 'DELIVERED', 'COMPLETED'],
      );
    });

    it('an insufficient-stock reserve is a 409 with structured short lines, and changes nothing', async () => {
      const order = await newOrder(5000);
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`);
      const res = await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: order.items[0].id, locationId: fx.locationId }] });
      assert.equal(res.status, 409);
      assert.match(res.json.message, /insufficient available stock/);
      assert.equal(res.json.shortLines[0].requested, 5000);
      assert.equal((await api.get(`/orders/${order.id}`)).json.status, 'APPROVED');
    });

    it('cancelling a reserved order releases it in the warehouse first', async () => {
      const order = await newOrder(2);
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`);
      await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: order.items[0].id, locationId: fx.locationId }] });
      const res = await api.post(`/orders/${order.id}/cancel`, { note: 'customer changed mind' });
      assert.equal(res.json.status, 'CANCELLED');
      assert.ok(warehouse.state.calls.some((c) => c.path === '/api/v1/stock/release' && c.body.reference === order.id));
    });

    it('a warehouse outage is a clean 503 and leaves the order untouched (retry is safe)', async () => {
      const order = await newOrder(1);
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`);
      warehouse.state.down = true;
      try {
        const res = await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: order.items[0].id, locationId: fx.locationId }] });
        assert.equal(res.status, 503);
        assert.match(res.json.message, /safe to retry/);
      } finally {
        warehouse.state.down = false;
      }
      assert.equal((await api.get(`/orders/${order.id}`)).json.status, 'APPROVED');
    });

    it('enforces the transition map and the reject note', async () => {
      const order = await newOrder(1);
      assert.equal((await api.post(`/orders/${order.id}/approve`)).status, 409, 'DRAFT cannot jump to APPROVED');
      await api.post(`/orders/${order.id}/submit`);
      assert.equal((await api.post(`/orders/${order.id}/reject`, { note: '   ' })).status, 400, 'whitespace is no reason');
      assert.equal((await api.post(`/orders/${order.id}/reject`, { note: 'credit hold' })).json.status, 'REJECTED');
    });

    it('cannot pick more than ordered', async () => {
      const order = await newOrder(2);
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`);
      await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: order.items[0].id, locationId: fx.locationId }] });
      const res = await api.post(`/orders/${order.id}/pick`, { items: [{ orderItemId: order.items[0].id, pickedQty: 3 }] });
      assert.equal(res.status, 400);
    });
  });

  describe('permissions and scoping', () => {
    it('a consultant sees only their own orders, and edits only their own drafts', async () => {
      const roles = (await api.get('/roles')).json;
      const consultantRole = roles.find((r) => r.name === 'CONSULTANT');
      const email = `c-${uid()}@test.local`;
      await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'Consultant', roleIds: [consultantRole.id] });
      const consultant = client(app.origin, (await loginAs(app.origin, { email, password: 'Passw0rd!x' })).accessToken);

      const adminOrder = await newOrder(1);
      const mine = (await consultant.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
      const visible = (await consultant.get('/orders')).json.map((o) => o.id);
      assert.ok(visible.includes(mine.id));
      assert.ok(!visible.includes(adminOrder.id));
      assert.equal((await consultant.get(`/orders/${adminOrder.id}`)).status, 404, 'not found, not forbidden');
      assert.equal((await consultant.post(`/orders/${mine.id}/approve`)).status, 403);
    });
  });

  describe('reports & audit', () => {
    it('reports aggregate orders by status; every mutation is audited', async () => {
      const report = (await api.get('/reports/orders')).json;
      assert.equal(report.count, report.orders.length);
      assert.ok(report.byStatus.some((s) => s.status === 'COMPLETED'));
      const dashboard = (await api.get('/dashboard')).json;
      assert.ok(dashboard.today.orderCount >= 1);

      await settle();
      const audit = (await api.get('/audit-logs?action=DISPATCH&pageSize=1')).json;
      assert.equal(audit.data[0].entity, 'orders');
      const login = (await api.get('/audit-logs?action=LOGIN&pageSize=1')).json.data[0];
      assert.equal(login.newValue.password, '[REDACTED]');
    });
  });
});
