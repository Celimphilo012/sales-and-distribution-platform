'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createFakeWarehouse, createTestApp, client, loginAs, uid } = require('./helpers');

const SOAP = '11111111-1111-4111-8111-111111111111'; // sellingPrice 12.5, costPrice 5
const NOCOST = '77777777-7777-4777-8777-777777777777'; // sellingPrice 20, no costPrice

describe('finances', () => {
  let warehouse;
  let app;
  let api; // admin
  const fx = {};

  before(async () => {
    warehouse = await createFakeWarehouse();
    app = await createTestApp({ warehouseApi: { url: warehouse.url, key: 'test-key' } });
    api = client(app.origin, (await loginAs(app.origin)).accessToken);
    fx.customer = (await api.post('/customers', { name: `Fin ${uid()}` })).json;
    fx.locationId = warehouse.state.locationId;
    warehouse.state.setStock(NOCOST, fx.locationId, 100);
  });

  after(async () => {
    await app.close();
    await warehouse.close();
  });

  /** Drives one order all the way to DISPATCHED (quantityFulfilled = quantity) for a given product/qty. */
  async function dispatchedOrder(productId, qty) {
    const order = (await api.post('/orders', { customerId: fx.customer.id, items: [{ productId, quantity: qty }] })).json;
    await api.post(`/orders/${order.id}/submit`);
    await api.post(`/orders/${order.id}/approve`, { note: 'ok' });
    const itemId = order.items[0].id;
    await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: itemId, locationId: fx.locationId }] });
    await api.post(`/orders/${order.id}/pick`, { items: [{ orderItemId: itemId, pickedQty: qty }] });
    await api.post(`/orders/${order.id}/pack`, { items: [{ orderItemId: itemId, packedQty: qty }] });
    await api.post(`/orders/${order.id}/ready`);
    const dispatched = await api.post(`/orders/${order.id}/dispatch`);
    assert.equal(dispatched.json.status, 'DISPATCHED');
    return dispatched.json;
  }

  describe('margin', () => {
    it('a line with no costPrice gets a null unitCost, excluded from the known-cost aggregate', async () => {
      const order = (await api.post('/orders', { customerId: fx.customer.id, items: [{ productId: NOCOST, quantity: 2 }] })).json;
      assert.equal(order.items[0].unitCost, null);
    });

    it('margin sums only rows with a known unit_cost, and reports what fraction of revenue that is', async () => {
      warehouse.state.setStock(SOAP, fx.locationId, 1000);
      await dispatchedOrder(SOAP, 10); // revenue 125, cost 50, margin 75
      await dispatchedOrder(NOCOST, 5); // revenue 100, unknown cost — excluded from margin/knownCostRevenue

      const res = await api.get('/finances/margin');
      assert.equal(res.status, 200);
      const soapRow = res.json.products.find((p) => p.productId === SOAP);
      assert.ok(soapRow, 'soap appears in the margin table');
      assert.ok(soapRow.margin >= 75, `expected at least 75 margin from this run, got ${soapRow.margin}`);
      assert.ok(!res.json.products.some((p) => p.productId === NOCOST), 'a product with no known cost is not in the margin table at all');
      assert.ok(res.json.totalRevenue >= res.json.knownCostRevenue, 'known-cost revenue never exceeds total revenue');
      assert.ok(res.json.knownCostRevenuePct < 100, 'the NOCOST sale pulls known-cost coverage below 100%');
    });

    it('requires finances.view', async () => {
      const noPerm = client(app.origin, (await loginAs(app.origin, (await makeConsultant()).creds)).accessToken);
      assert.equal((await noPerm.get('/finances/margin')).status, 403);
    });
  });

  describe('expenses', () => {
    it('records, lists, and voids an expense; a second void is refused', async () => {
      const rec = await api.post('/finances/expenses', { category: 'UTILITIES', amount: 150.5, incurredAt: '2026-10-01', description: 'Electricity' });
      assert.equal(rec.status, 201);
      assert.equal(rec.json.status, 'RECORDED');
      assert.equal(rec.json.amount, '150.5');

      const list = await api.get('/finances/expenses?category=UTILITIES');
      assert.ok(list.json.some((e) => e.id === rec.json.id));

      const voided = await api.post(`/finances/expenses/${rec.json.id}/void`, { reason: 'Entered twice' });
      assert.equal(voided.status, 200);
      assert.equal(voided.json.status, 'VOIDED');
      assert.equal(voided.json.voidReason, 'Entered twice');

      const again = await api.post(`/finances/expenses/${rec.json.id}/void`, { reason: 'retry' });
      assert.equal(again.status, 409);
    });

    it('refuses a zero-length void reason', async () => {
      const rec = await api.post('/finances/expenses', { category: 'OTHER', amount: 10, incurredAt: '2026-10-01' });
      assert.equal((await api.post(`/finances/expenses/${rec.json.id}/void`, { reason: '' })).status, 400);
    });
  });

  describe('AR aging', () => {
    it('buckets an outstanding order by how many days old its order_date is', async () => {
      const order = (await api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`, { note: 'ok' });
      // Backdate order_date 45 days so it lands in the 31-60 bucket — no API sets order_date directly.
      const past = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000);
      await app.db.exec('UPDATE orders SET order_date = ? WHERE id = ?', [past, order.id]);

      const res = await api.get('/finances/summary');
      assert.equal(res.status, 200);
      const bucket3160 = res.json.aging.find((b) => b.bucket === '31-60');
      assert.ok(bucket3160.amount > 0, 'the backdated order is counted in the 31-60 bucket');
      assert.deepEqual(res.json.aging.map((b) => b.bucket), ['0-30', '31-60', '61-90', '90+'], 'buckets always present, in order, even at 0');
    });
  });

  describe('customer statement', () => {
    it('merges orders and payments into a dated ledger with a running balance', async () => {
      const customer = (await api.post('/customers', { name: `Statement ${uid()}` })).json;
      const order = (await api.post('/orders', { customerId: customer.id, items: [{ productId: SOAP, quantity: 2 }] })).json; // total 25
      await api.post(`/orders/${order.id}/submit`);
      await api.post(`/orders/${order.id}/approve`, { note: 'ok' });

      const payment = await api.post('/payments', { orderId: order.id, amount: 10, method: 'CASH' });
      assert.equal(payment.status, 201);

      const stmt = await api.get(`/finances/statements/${customer.id}`);
      assert.equal(stmt.status, 200);
      assert.equal(stmt.json.bought, 25);
      assert.equal(stmt.json.paid, 10);
      assert.equal(stmt.json.balanceDue, 15);
      assert.equal(stmt.json.entries.length, 2);
      assert.equal(stmt.json.entries[0].type, 'ORDER');
      assert.equal(stmt.json.entries[0].balance, 25);
      assert.equal(stmt.json.entries[1].type, 'PAYMENT');
      assert.equal(stmt.json.entries[1].balance, 15);

      await api.post(`/payments/${payment.json.payment.id}/void`, { reason: 'mistake' });
      const after2 = await api.get(`/finances/statements/${customer.id}`);
      assert.equal(after2.json.paid, 0, 'a voided payment no longer counts as paid');
      assert.equal(after2.json.balanceDue, 25);
      const voidedEntry = after2.json.entries.find((e) => e.type === 'PAYMENT');
      assert.equal(voidedEntry.status, 'VOIDED', 'the voided payment still appears in the ledger, just with no balance effect');
      assert.equal(voidedEntry.balance, 25, 'its running balance reflects effect 0, not a subtraction');
    });
  });

  async function makeConsultant() {
    const email = `consultant-${uid()}@test.local`;
    const password = 'TestPass123!';
    const role = (await api.get('/roles')).json.find((r) => r.name === 'CONSULTANT');
    await api.post('/users', { email, fullName: 'Consultant Test', password, roleIds: [role.id] });
    return { creds: { email, password } };
  }
});
