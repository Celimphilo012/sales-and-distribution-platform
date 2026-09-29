'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { planAllocation } = require('../src/modules/stock-allocation');
const { createFakeWarehouse, createTestApp, client, loginAs, uid } = require('./helpers');

const OLD = '2026-01-01T00:00:00.000Z';
const MID = '2026-03-01T00:00:00.000Z';
const NEW = '2026-06-01T00:00:00.000Z';

describe('planAllocation (the automatic reservation plan)', () => {
  const loc = (locationId, warehouseId, available, oldestStockAt) => ({ locationId, warehouseId, available, oldestStockAt });

  it('takes the oldest stock first, splitting a line across locations when needed', () => {
    const plan = planAllocation(
      [{ id: 'i1', productId: 'p', quantity: 10 }],
      [{ productId: 'p', locations: [loc('new', 'w1', 50, NEW), loc('old', 'w1', 6, OLD), loc('mid', 'w1', 3, MID)] }],
    );
    assert.equal(plan.complete, true);
    assert.equal(plan.warehouseId, 'w1');
    assert.deepEqual(plan.lines[0].allocations, [
      { locationId: 'old', quantity: 6 },
      { locationId: 'mid', quantity: 3 },
      { locationId: 'new', quantity: 1 },
    ]);
  });

  it('keeps an order in ONE warehouse, choosing one that can fill it all', () => {
    const plan = planAllocation(
      [
        { id: 'i1', productId: 'a', quantity: 5 },
        { id: 'i2', productId: 'b', quantity: 5 },
      ],
      [
        // w2 has the older stock of "a" but no "b" at all; only w1 can fill the whole order.
        { productId: 'a', locations: [loc('a2', 'w2', 9, OLD), loc('a1', 'w1', 9, NEW)] },
        { productId: 'b', locations: [loc('b1', 'w1', 9, NEW)] },
      ],
    );
    assert.equal(plan.warehouseId, 'w1');
    assert.equal(plan.complete, true);
    assert.deepEqual(plan.lines.map((l) => l.allocations[0].locationId), ['a1', 'b1']);
    assert.deepEqual(plan.alternatives.find((a) => a.warehouseId === 'w2').complete, false);
  });

  it('two lines of the same product share one pool of stock', () => {
    const plan = planAllocation(
      [
        { id: 'i1', productId: 'p', quantity: 4 },
        { id: 'i2', productId: 'p', quantity: 4 },
      ],
      [{ productId: 'p', locations: [loc('x', 'w1', 5, OLD), loc('y', 'w1', 5, NEW)] }],
    );
    assert.deepEqual(plan.lines[0].allocations, [{ locationId: 'x', quantity: 4 }]);
    assert.deepEqual(plan.lines[1].allocations, [
      { locationId: 'x', quantity: 1 },
      { locationId: 'y', quantity: 3 },
    ]);
  });

  it('when no warehouse can fill the order: the closest one, marked incomplete with the shortfall', () => {
    const plan = planAllocation(
      [{ id: 'i1', productId: 'p', quantity: 10 }],
      [{ productId: 'p', locations: [loc('x', 'w1', 7, OLD), loc('z', 'w2', 3, OLD)] }],
    );
    assert.equal(plan.complete, false);
    assert.equal(plan.warehouseId, 'w1');
    assert.equal(plan.lines[0].shortBy, 3);

    const none = planAllocation([{ id: 'i1', productId: 'p', quantity: 2 }], [{ productId: 'p', locations: [] }]);
    assert.equal(none.warehouseId, null);
    assert.equal(none.lines[0].shortBy, 2);
  });

  it('can plan in a warehouse the manager chose', () => {
    const plan = planAllocation(
      [{ id: 'i1', productId: 'p', quantity: 2 }],
      [{ productId: 'p', locations: [loc('x', 'w1', 7, OLD), loc('z', 'w2', 3, NEW)] }],
      { warehouseId: 'w2' },
    );
    assert.deepEqual(plan.lines[0].allocations, [{ locationId: 'z', quantity: 2 }]);
  });
});

describe('reserving stock (automatic plan, override, dispatch)', () => {
  const SOAP = '11111111-1111-4111-8111-111111111111';
  const [BIN, SHELF_B, SHELF_C, FAR] = [
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    '55555555-5555-4555-8555-555555555555',
    '66666666-6666-4666-8666-666666666666',
  ];
  let warehouse;
  let app;
  let api;
  let customer;

  before(async () => {
    warehouse = await createFakeWarehouse();
    app = await createTestApp({ warehouseApi: { url: warehouse.url, key: 'test-key' } });
    api = client(app.origin, (await loginAs(app.origin)).accessToken);
    customer = (await api.post('/customers', { name: `Alloc ${uid()}` })).json;
  });
  after(async () => {
    await app.close();
    await warehouse.close();
  });

  /** Fresh stock layout for each test: soap in three W1 locations of different ages, and in W2. */
  function stock({ bin = 0, shelfB = 0, shelfC = 0, far = 0, farAge = OLD } = {}) {
    warehouse.state.setStock(SOAP, BIN, bin, NEW);
    warehouse.state.setStock(SOAP, SHELF_B, shelfB, OLD);
    warehouse.state.setStock(SOAP, SHELF_C, shelfC, MID);
    warehouse.state.setStock(SOAP, FAR, far, farAge);
  }

  async function approvedOrder(qty) {
    const order = (await api.post('/orders', { customerId: customer.id, items: [{ productId: SOAP, quantity: qty }] })).json;
    await api.post(`/orders/${order.id}/submit`, {});
    return (await api.post(`/orders/${order.id}/approve`, {})).json;
  }

  it('proposes oldest stock first within one warehouse, with the alternatives and every option', async () => {
    stock({ bin: 50, shelfB: 6, shelfC: 3, far: 100, farAge: NEW });
    const order = await approvedOrder(10);
    const res = await api.get(`/orders/${order.id}/reservation-proposal`);
    assert.equal(res.status, 200, res.body);
    assert.equal(res.json.complete, true);
    // Both warehouses can fill it; Main WH holds the older stock.
    assert.equal(res.json.warehouse.name, 'Main WH');
    const [line] = res.json.lines;
    assert.deepEqual(
      line.allocations.map((a) => [a.label, a.quantity]),
      [
        ['Shelf B', 6],
        ['Shelf C', 3],
        ['Bin', 1],
      ],
    );
    assert.equal(line.options.length, 3, 'every W1 location holding soap is offered for an override');
    assert.deepEqual(res.json.alternatives.map((a) => a.name).sort(), ['Far WH', 'Main WH']);

    // When the other warehouse's stock is older, the order goes there (still one warehouse)...
    stock({ bin: 50, shelfB: 6, shelfC: 3, far: 100, farAge: '2025-06-01T00:00:00.000Z' });
    assert.equal((await api.get(`/orders/${order.id}/reservation-proposal`)).json.warehouse.name, 'Far WH');
    // ...unless the manager asks for a specific one.
    const chosen = await api.get(`/orders/${order.id}/reservation-proposal?warehouseId=w1`);
    assert.equal(chosen.status, 400, 'warehouse ids are validated as UUIDs');
  });

  it('reserves automatically (no allocations sent), split across locations, and dispatch ships from them', async () => {
    stock({ bin: 50, shelfB: 6, shelfC: 3 });
    const order = await approvedOrder(10);
    const reserved = await api.post(`/orders/${order.id}/reserve`, {});
    assert.equal(reserved.status, 201, reserved.body);
    assert.equal(reserved.json.status, 'STOCK_RESERVED');
    assert.deepEqual(
      reserved.json.items[0].allocations.map((a) => [a.locationId, Number(a.quantity)]),
      [
        [SHELF_B, 6],
        [SHELF_C, 3],
        [BIN, 1],
      ],
    );
    assert.equal(reserved.json.items[0].reservedLocationId, SHELF_B, 'the first location stays the primary one');
    assert.deepEqual(
      reserved.json.items[0].allocations.map((a) => a.locationLabel),
      ['Shelf B', 'Shelf C', 'Bin'],
      'location names are saved with the reservation, for pickers',
    );
    const call = warehouse.state.calls.filter((c) => c.path === '/api/v1/stock/reserve' && c.body.reference === order.id).at(-1);
    assert.equal(call.body.lines.length, 3);
    assert.equal(warehouse.state.availableAt(SOAP, SHELF_B), 0);

    // Pick all, pack 8 of 10: dispatch takes 6 from Shelf B and 2 from Shelf C, and releases the rest.
    const itemId = order.items[0].id;
    await api.post(`/orders/${order.id}/pick`, { items: [{ orderItemId: itemId, pickedQty: 10 }] });
    await api.post(`/orders/${order.id}/pack`, { items: [{ orderItemId: itemId, packedQty: 8 }] });
    await api.post(`/orders/${order.id}/ready`, {});
    const dispatched = await api.post(`/orders/${order.id}/dispatch`, {});
    assert.equal(dispatched.status, 201, dispatched.body);
    assert.equal(dispatched.json.status, 'PARTIALLY_FULFILLED');
    assert.equal(Number(dispatched.json.items[0].quantityFulfilled), 8);
    const issue = warehouse.state.calls.find((c) => c.path === '/api/v1/stock/issue' && c.body.reference === order.id);
    assert.deepEqual(
      issue.body.lines.map((l) => [l.locationId, l.quantity]),
      [
        [SHELF_B, 6],
        [SHELF_C, 2],
      ],
    );
    assert.equal(warehouse.state.availableAt(SOAP, SHELF_C), 1, 'the unshipped unit went back to Shelf C');
    assert.equal(warehouse.state.availableAt(SOAP, BIN), 50, 'the unshipped unit went back to the Bin');
  });

  it('refuses when no single warehouse holds enough — even if the total across warehouses would', async () => {
    stock({ bin: 3, far: 3 });
    const order = await approvedOrder(5);
    const res = await api.post(`/orders/${order.id}/reserve`, {});
    assert.equal(res.status, 409);
    assert.match(res.json.message, /no single warehouse has enough stock/);
    assert.equal(res.json.shortLines[0].requested, 5);
    assert.equal(res.json.shortLines[0].available, 3);
    assert.equal((await api.get(`/orders/${order.id}`)).json.status, 'APPROVED', 'nothing changed');
  });

  it("a manager's override is honoured; a location without the stock fails the whole reservation", async () => {
    stock({ bin: 50, shelfB: 2 });
    const order = await approvedOrder(4);
    const itemId = order.items[0].id;

    const tooMuch = await api.post(`/orders/${order.id}/reserve`, { allocations: [{ orderItemId: itemId, locationId: SHELF_B }] });
    assert.equal(tooMuch.status, 409, 'Shelf B has only 2');
    assert.equal(tooMuch.json.shortLines[0].locationId, SHELF_B);
    assert.equal(warehouse.state.availableAt(SOAP, SHELF_B), 2, 'nothing was reserved');
    assert.equal((await api.get(`/orders/${order.id}`)).json.status, 'APPROVED');

    const wrongSum = await api.post(`/orders/${order.id}/reserve`, {
      allocations: [
        { orderItemId: itemId, locationId: SHELF_B, quantity: 2 },
        { orderItemId: itemId, locationId: BIN, quantity: 1 },
      ],
    });
    assert.equal(wrongSum.status, 400);
    assert.match(wrongSum.json.message, /add up to 3, but the line is for 4/);

    const twoWarehouses = await api.post(`/orders/${order.id}/reserve`, {
      allocations: [
        { orderItemId: itemId, locationId: SHELF_B, quantity: 2 },
        { orderItemId: itemId, locationId: FAR, quantity: 2 },
      ],
    });
    assert.equal(twoWarehouses.status, 400);
    assert.match(twoWarehouses.json.message, /one warehouse/);

    const ok = await api.post(`/orders/${order.id}/reserve`, {
      allocations: [
        { orderItemId: itemId, locationId: BIN, quantity: 3 },
        { orderItemId: itemId, locationId: SHELF_B, quantity: 1 },
      ],
    });
    assert.equal(ok.status, 201, ok.body);
    assert.deepEqual(
      ok.json.items[0].allocations.map((a) => [a.locationId, Number(a.quantity)]),
      [
        [BIN, 3],
        [SHELF_B, 1],
      ],
    );
  });

  it('only an APPROVED order can be planned', async () => {
    const draft = (await api.post('/orders', { customerId: customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
    assert.equal((await api.get(`/orders/${draft.id}/reservation-proposal`)).status, 409);
  });
});
