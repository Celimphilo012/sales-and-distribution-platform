'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createFakeWarehouse, createTestApp, client, loginAs, uid } = require('./helpers');

const SOAP = '11111111-1111-4111-8111-111111111111'; // sellingPrice 12.5 in the fake warehouse

describe('sale campaign pricing (ordering side)', () => {
  let warehouse;
  let app;
  let api; // admin
  const fx = {};

  before(async () => {
    warehouse = await createFakeWarehouse();
    app = await createTestApp({ warehouseApi: { url: warehouse.url, key: 'test-key' } });
    api = client(app.origin, (await loginAs(app.origin)).accessToken);
    fx.customerA = (await api.post('/customers', { name: `Eligible ${uid()}` })).json;
    fx.customerB = (await api.post('/customers', { name: `Not eligible ${uid()}` })).json;

    // A consultant user, assigned to customerB — eligibility is granted by consultant, so customerB
    // (assigned to this consultant) is the one who can become eligible; customerA stays unassigned
    // (no consultant = never eligible, fails closed).
    const consultantRole = (await api.post('/roles', { name: `Consultant-${uid()}` })).json;
    const allPerms = (await api.get('/permissions')).json;
    await api.put(`/roles/${consultantRole.id}/permissions`, {
      permissionIds: allPerms.filter((p) => p.key === 'orders.create').map((p) => p.id),
    });
    const consultantEmail = `consultant-${uid()}@test.local`;
    fx.consultant = (
      await api.post('/users', { email: consultantEmail, password: 'Passw0rd!x', fullName: 'Consultant', roleIds: [consultantRole.id] })
    ).json;
    await api.patch(`/customers/${fx.customerB.id}`, { assignedConsultantId: fx.consultant.id });
  });

  after(async () => {
    await app.close();
    await warehouse.close();
  });

  const orderWith = async (customerId, qty) => (await api.post('/orders', { customerId, items: [{ productId: SOAP, quantity: qty }] })).json;

  it('no sale on the product: plain price, no discount fields set', async () => {
    const order = await orderWith(fx.customerA.id, 4);
    assert.equal(order.items[0].unitPrice, '12.5');
    assert.equal(order.items[0].originalUnitPrice, null);
    assert.equal(order.items[0].saleCampaignId, null);
  });

  it('an ALL_CUSTOMERS sale discounts the line once the minimum quantity is met', async () => {
    warehouse.state.setSale(SOAP, { campaignId: 'c0000000-0000-4000-8000-00000000a111', campaignName: 'Everyone sale', discountType: 'PERCENT', discountValue: 20, minQuantity: 3, sellingPrice: 12.5 });

    const tooFew = await orderWith(fx.customerA.id, 2);
    assert.equal(tooFew.items[0].unitPrice, '12.5', 'below minQuantity — no discount');
    assert.equal(tooFew.items[0].saleCampaignId, null);

    const enough = await orderWith(fx.customerA.id, 3);
    assert.equal(Number(enough.items[0].unitPrice), 10); // 12.5 - 20%
    assert.equal(Number(enough.items[0].originalUnitPrice), 12.5);
    assert.equal(enough.items[0].saleCampaignId, 'c0000000-0000-4000-8000-00000000a111');
    assert.equal(enough.items[0].saleCampaignName, 'Everyone sale');
    assert.equal(Number(enough.items[0].lineTotal), 30);

    warehouse.state.clearSale(SOAP);
  });

  it('a per-customer usage cap stops applying once a customer has used it enough times', async () => {
    warehouse.state.setSale(SOAP, {
      campaignId: 'c0000000-0000-4000-8000-00000000cap1',
      campaignName: 'Capped sale',
      discountType: 'FIXED_AMOUNT',
      discountValue: 2,
      minQuantity: 1,
      maxUsesPerCustomer: 2,
      sellingPrice: 12.5,
    });

    const first = await orderWith(fx.customerA.id, 1);
    assert.equal(Number(first.items[0].unitPrice), 10.5, 'use 1 of 2 — discounted');

    const second = await orderWith(fx.customerA.id, 1);
    assert.equal(Number(second.items[0].unitPrice), 10.5, 'use 2 of 2 — still discounted');

    const third = await orderWith(fx.customerA.id, 1);
    assert.equal(third.items[0].unitPrice, '12.5', 'use 3 — cap reached, full price');
    assert.equal(third.items[0].saleCampaignId, null);

    // a different customer has their own, separate count
    const otherCustomer = await orderWith(fx.customerB.id, 1);
    assert.equal(Number(otherCustomer.items[0].unitPrice), 10.5, 'a different customer is unaffected by customerA\'s usage');

    warehouse.state.clearSale(SOAP);
  });

  it('no cap set (undefined) never limits usage', async () => {
    warehouse.state.setSale(SOAP, {
      campaignId: 'c0000000-0000-4000-8000-00000000cap2',
      campaignName: 'Uncapped sale',
      discountType: 'FIXED_AMOUNT',
      discountValue: 1,
      minQuantity: 1,
      sellingPrice: 12.5,
    });
    for (let i = 0; i < 3; i++) {
      const order = await orderWith(fx.customerA.id, 1);
      assert.equal(Number(order.items[0].unitPrice), 11.5, `use ${i + 1} — still discounted, no cap`);
    }
    warehouse.state.clearSale(SOAP);
  });

  it('editing a DRAFT re-resolves pricing against the order\'s own (immutable) customer', async () => {
    warehouse.state.setSale(SOAP, { campaignId: 'c0000000-0000-4000-8000-00000000ed17', campaignName: 'Edit sale', discountType: 'FIXED_AMOUNT', discountValue: 2, minQuantity: 1, sellingPrice: 12.5 });
    const order = await orderWith(fx.customerA.id, 1);
    assert.equal(Number(order.items[0].unitPrice), 10.5);

    warehouse.state.clearSale(SOAP);
    const edited = (await api.patch(`/orders/${order.id}`, { items: [{ productId: SOAP, quantity: 1 }] })).json;
    assert.equal(edited.items[0].unitPrice, '12.5', 'sale ended — editing re-resolves to the current (now plain) price');
  });

  it('a RESTRICTED sale is not discounted for a customer who is not on the eligible list', async () => {
    warehouse.state.setSale(SOAP, {
      campaignId: 'c0000000-0000-4000-8000-0000000005e5',
      campaignName: 'VIP sale',
      discountType: 'FIXED_PRICE',
      discountValue: 9,
      minQuantity: 1,
      eligibility: 'RESTRICTED',
      sellingPrice: 12.5,
    });

    const notEligible = await orderWith(fx.customerB.id, 1);
    assert.equal(notEligible.items[0].unitPrice, '12.5');
    assert.equal(notEligible.items[0].saleCampaignId, null);
  });

  it('GET /sales relays the warehouse\'s campaign list', async () => {
    const res = await api.get('/sales');
    assert.equal(res.status, 200);
    assert.ok(res.json.campaigns.some((c) => c.id === 'c0000000-0000-4000-8000-0000000005e5'));
  });

  it('managing the eligible-consultants list needs sales.eligibility.manage, and makes the RESTRICTED sale apply to every customer under that consultant', async () => {
    const scoped = await (async () => {
      const role = (await api.post('/roles', { name: `Viewer-${uid()}` })).json;
      const perms = (await api.get('/permissions')).json;
      await api.put(`/roles/${role.id}/permissions`, { permissionIds: perms.filter((p) => ['sales.view', 'orders.create'].includes(p.key)).map((p) => p.id) });
      const email = `viewer-${uid()}@test.local`;
      await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'Viewer', roleIds: [role.id] });
      return client(app.origin, (await loginAs(app.origin, { email, password: 'Passw0rd!x' })).accessToken);
    })();
    assert.equal(
      (await scoped.put('/sales/c0000000-0000-4000-8000-0000000005e5/eligible-consultants', { consultantIds: [fx.consultant.id] })).status,
      403,
    );

    const set = await api.put('/sales/c0000000-0000-4000-8000-0000000005e5/eligible-consultants', { consultantIds: [fx.consultant.id] });
    assert.equal(set.status, 200);
    assert.equal(set.json.length, 1);
    assert.equal(set.json[0].consultant.id, fx.consultant.id);

    // customerB is assigned to the now-eligible consultant — discount applies
    const nowEligible = await orderWith(fx.customerB.id, 1);
    assert.equal(Number(nowEligible.items[0].unitPrice), 9);
    assert.equal(nowEligible.items[0].saleCampaignId, 'c0000000-0000-4000-8000-0000000005e5');

    // customerA has no assigned consultant at all — still full price (fails closed)
    const stillNotEligible = await orderWith(fx.customerA.id, 1);
    assert.equal(stillNotEligible.items[0].unitPrice, '12.5');

    // replacing with an empty list clears eligibility
    await api.put('/sales/c0000000-0000-4000-8000-0000000005e5/eligible-consultants', { consultantIds: [] });
    assert.equal((await api.get('/sales/c0000000-0000-4000-8000-0000000005e5/eligible-consultants')).json.length, 0);
    warehouse.state.clearSale(SOAP);
  });

  it('GET /users/consultants lists only active users holding orders.create', async () => {
    const res = await api.get('/users/consultants');
    assert.equal(res.status, 200);
    assert.ok(res.json.some((u) => u.id === fx.consultant.id));
    assert.ok(!res.json.some((u) => u.fullName === undefined)); // shape sanity: fullName present
  });
});
