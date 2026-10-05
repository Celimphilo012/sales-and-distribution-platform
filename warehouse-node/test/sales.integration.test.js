'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createTestApp, client, loginAs, uid } = require('./helpers');

describe('sale campaigns', () => {
  let app;
  let api; // admin client
  let scheduler; // sales.schedule only
  let scheduler2; // sales.schedule only — a second requester, for "only the requester can edit"
  let approver; // sales.approve only
  let approver2; // sales.approve only — a second reviewer, for re-approval-after-reopen tests
  const run = uid();
  const fx = {};

  const future = (days) => new Date(Date.now() + days * 86_400_000).toISOString();
  const past = (ms = 1000) => new Date(Date.now() - ms).toISOString();

  before(async () => {
    app = await createTestApp({ cronSecret: 'test-cron-secret' });
    const { accessToken } = await loginAs(app);
    api = client(app, { token: accessToken });

    const warehouse = (await api.post('/warehouses', { name: `WH ${run}`, code: `WH-${run}` })).json;
    fx.warehouseId = warehouse.id;
    const workstream = (await api.post('/workstreams', { warehouseId: warehouse.id, name: `WS ${run}`, code: `WS-${run}` })).json;
    fx.category = (await api.post('/categories', { name: `Cat ${run}`, workstreamId: workstream.id })).json;

    const product = async (sku, price) =>
      (await api.post('/products', { sku: `${sku}-${run}`, name: `${sku} ${run}`, categoryId: fx.category.id, sellingPrice: price, uom: 'EACH' })).json;
    fx.productA = await product('SALE-A', 100);
    fx.productB = await product('SALE-B', 50);

    const perms = (await api.get('/permissions')).json;
    const permIds = (keys) => perms.filter((p) => keys.includes(p.key)).map((p) => p.id);

    async function makeUser(label, permissionKeys) {
      const role = (await api.post('/roles', { name: `${label}-${run}` })).json;
      await api.put(`/roles/${role.id}/permissions`, { permissionIds: permIds(permissionKeys) });
      const email = `${label.toLowerCase()}-${run}@test.local`;
      const userId = (await api.post('/users', { email, password: 'Passw0rd!x', fullName: label, roleIds: [role.id] })).json.id;
      await api.put(`/users/${userId}/warehouses`, { warehouseIds: [fx.warehouseId] }); // access is deny-by-default
      return client(app, { token: (await loginAs(app, { email, password: 'Passw0rd!x' })).accessToken });
    }
    scheduler = await makeUser('Scheduler', ['catalogue.view', 'sales.view', 'sales.schedule']);
    scheduler2 = await makeUser('Scheduler2', ['catalogue.view', 'sales.view', 'sales.schedule']);
    approver = await makeUser('Approver', ['catalogue.view', 'sales.view', 'sales.approve']);
    approver2 = await makeUser('Approver2', ['catalogue.view', 'sales.view', 'sales.approve']);
  });

  after(async () => {
    await app.close();
  });

  it('scheduling never makes it live', async () => {
    const res = await scheduler.post('/sales', {
      name: `Campaign ${run}`,
      startsAt: future(1),
      endsAt: future(8),
      products: [{ productId: fx.productA.id, discountType: 'PERCENT', discountValue: 20, minQuantity: 3 }],
    });
    assert.equal(res.status, 201);
    assert.equal(res.json.status, 'PENDING_APPROVAL');
    fx.campaignId = res.json.id;
    // Decimal columns come back as strings (same convention as every other ledger/money field in
    // this API — see InventoryService.findTransactions) — the client is expected to Number() it.
    assert.equal(Number(res.json.products[0].minQuantity), 3);
    assert.equal((await api.get(`/products/${fx.productA.id}`)).json.sale, undefined);
  });

  it('the scheduler cannot approve (no permission)', async () => {
    assert.equal((await scheduler.post(`/sales/${fx.campaignId}/approve`, {})).status, 403);
  });

  it('nobody can approve their own campaign, even with the permission', async () => {
    const own = (
      await api.post('/sales', {
        name: `Own ${run}`,
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: fx.productB.id, discountType: 'FIXED_AMOUNT', discountValue: 5 }],
      })
    ).json;
    const res = await api.post(`/sales/${own.id}/approve`, {});
    assert.equal(res.status, 403);
    assert.match(res.json.message, /cannot approve your own/);
    await api.post(`/sales/${own.id}/reject`, { reviewNote: 'test cleanup, frees productB' });
  });

  it('a rejected campaign requires a note, and moves no pricing', async () => {
    const req = (
      await scheduler.post('/sales', {
        name: `ToReject ${run}`,
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: fx.productB.id, discountType: 'FIXED_AMOUNT', discountValue: 5 }],
      })
    ).json;
    assert.equal((await approver.post(`/sales/${req.id}/reject`, {})).status, 400);
    const res = await approver.post(`/sales/${req.id}/reject`, { reviewNote: 'not now' });
    assert.equal(res.json.status, 'REJECTED');
  });

  it('approving (by someone else) lands on SCHEDULED, since startsAt is in the future', async () => {
    const res = await approver.post(`/sales/${fx.campaignId}/approve`, { reviewNote: 'looks good' });
    assert.equal(res.status, 201);
    assert.equal(res.json.status, 'SCHEDULED');
    assert.equal((await api.get(`/products/${fx.productA.id}`)).json.sale, undefined); // not live yet
  });

  it('cannot approve twice', async () => {
    assert.equal((await approver.post(`/sales/${fx.campaignId}/approve`, {})).status, 409);
  });

  it('a product can only be on one PENDING_APPROVAL/SCHEDULED/ACTIVE campaign at a time', async () => {
    const res = await scheduler.post('/sales', {
      name: `Overlap ${run}`,
      startsAt: future(1),
      endsAt: future(5),
      products: [{ productId: fx.productA.id, discountType: 'PERCENT', discountValue: 10 }],
    });
    assert.equal(res.status, 409);
    assert.match(res.json.message, /already on the sale campaign/);
  });

  it('endsAt must be after startsAt', async () => {
    const res = await scheduler.post('/sales', {
      name: `Bad window ${run}`,
      startsAt: future(5),
      endsAt: future(1),
      products: [{ productId: fx.productB.id, discountType: 'PERCENT', discountValue: 10 }],
    });
    assert.equal(res.status, 400);
  });

  it('sales-tick flips SCHEDULED -> ACTIVE once startsAt has passed; the product then reads as on sale', async () => {
    await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), fx.campaignId]);
    const res = await app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'test-cron-secret' } });
    assert.equal(res.statusCode, 201);
    assert.deepEqual(res.json(), { started: 1, ended: 0, paused: 0 });

    assert.equal((await api.get(`/sales/${fx.campaignId}`)).json.status, 'ACTIVE');

    const product = (await api.get(`/products/${fx.productA.id}`)).json;
    assert.equal(product.sale.campaignId, fx.campaignId);
    assert.equal(product.sale.discountType, 'PERCENT');
    assert.equal(product.sale.minQuantity, 3);
    assert.equal(product.sale.effectivePrice, 80); // 100 - 20%
  });

  it('a running tick with nothing due flips nothing', async () => {
    // Not "nothing in the whole table is due" — this suite doesn't clean up rows between tests (the
    // codebase-wide convention here is unique names per test, not per-test DB resets), so other
    // tests' campaigns can legitimately still be due by the time this one runs. Tick once to settle
    // anything genuinely outstanding, then assert the SECOND call — immediately after — is a no-op.
    await app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'test-cron-secret' } });
    const res = await app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'test-cron-secret' } });
    assert.deepEqual(res.json(), { started: 0, ended: 0, paused: 0 });
  });

  it('the external catalogue API carries the same sale block, and GET /api/v1/sales lists it', async () => {
    const key = (await api.post('/api-keys', { name: `sales-test-${run}`, scopes: ['catalogue:read'] })).json;
    const ext = client(app, { headers: { 'x-api-key': key.rawKey } });

    const catalogue = await ext.get('/api/v1/catalogue');
    const relayed = catalogue.json.products.find((p) => p.id === fx.productA.id);
    assert.equal(relayed.sale.campaignId, fx.campaignId);
    assert.equal(relayed.sale.effectivePrice, 80);

    const sales = await ext.get('/api/v1/sales');
    assert.ok(sales.json.campaigns.some((c) => c.id === fx.campaignId && c.status === 'ACTIVE'));
  });

  it('sales-tick flips ACTIVE -> ENDED once endsAt has passed, and pricing reverts', async () => {
    await app.db.exec('UPDATE sale_campaigns SET ends_at = ? WHERE id = ?', [new Date(past()), fx.campaignId]);
    const res = await app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'test-cron-secret' } });
    assert.deepEqual(res.json(), { started: 0, ended: 1, paused: 0 });
    assert.equal((await api.get(`/sales/${fx.campaignId}`)).json.status, 'ENDED');
    assert.equal((await api.get(`/products/${fx.productA.id}`)).json.sale, undefined);
  });

  it('ENDED frees the product for a new campaign', async () => {
    const res = await scheduler.post('/sales', {
      name: `Reuse A ${run}`,
      startsAt: future(1),
      endsAt: future(2),
      products: [{ productId: fx.productA.id, discountType: 'FIXED_PRICE', discountValue: 65 }],
    });
    assert.equal(res.status, 201);
  });

  it('the internal tick endpoint 404s without the right secret, and when CRON_SECRET is unset', async () => {
    assert.equal((await app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'wrong' } })).statusCode, 404);
    assert.equal((await app.inject({ method: 'POST', url: '/internal/sales-tick' })).statusCode, 404);
    const noSecret = await createTestApp();
    assert.equal((await noSecret.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': '' } })).statusCode, 404);
    await noSecret.close();
  });

  it('cancel ends a SCHEDULED or ACTIVE campaign early, with the same confirmation tier as approve/reject', async () => {
    const campaign = (
      await scheduler.post('/sales', {
        name: `Cancel me ${run}`,
        startsAt: future(1),
        endsAt: future(5),
        products: [{ productId: fx.productB.id, discountType: 'FIXED_PRICE', discountValue: 40 }],
      })
    ).json;
    await approver.post(`/sales/${campaign.id}/approve`, {});
    assert.equal((await scheduler.post(`/sales/${campaign.id}/cancel`, {})).status, 403); // scheduler lacks sales.approve
    const res = await approver.post(`/sales/${campaign.id}/cancel`, { reviewNote: 'changed plans' });
    assert.equal(res.json.status, 'CANCELLED');
    assert.equal((await approver.post(`/sales/${campaign.id}/cancel`, {})).status, 409); // already terminal
  });

  it('a user outside the campaign\'s warehouse cannot see or approve it', async () => {
    const otherWarehouse = (await api.post('/warehouses', { name: `Other WH ${run}`, code: `OWH-${run}` })).json;
    const perms = (await api.get('/permissions')).json;
    const role = (await api.post('/roles', { name: `Outsider-${run}` })).json;
    await api.put(`/roles/${role.id}/permissions`, { permissionIds: perms.filter((p) => ['sales.view', 'sales.approve'].includes(p.key)).map((p) => p.id) });
    const email = `outsider-${run}@test.local`;
    const userId = (await api.post('/users', { email, password: 'Passw0rd!x', fullName: 'Outsider', roleIds: [role.id] })).json.id;
    await api.put(`/users/${userId}/warehouses`, { warehouseIds: [otherWarehouse.id] });
    const outsider = client(app, { token: (await loginAs(app, { email, password: 'Passw0rd!x' })).accessToken });

    assert.equal((await outsider.get(`/sales/${fx.campaignId}`)).status, 403);
    assert.equal((await outsider.get('/sales')).json.some((c) => c.id === fx.campaignId), false);
  });

  const product = async (sku, price) =>
    (await api.post('/products', { sku: `${sku}-${run}`, name: `${sku} ${run}`, categoryId: fx.category.id, sellingPrice: price, uom: 'EACH' })).json;
  const tick = () => app.inject({ method: 'POST', url: '/internal/sales-tick', headers: { 'x-cron-secret': 'test-cron-secret' } });

  describe('editing and reopening', () => {
    it('editPending rejects once the campaign is no longer PENDING_APPROVAL', async () => {
      const p = await product('EDIT-GONE', 20);
      const created = (
        await scheduler.post('/sales', {
          name: `EditGone ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/approve`, {});
      const res = await scheduler.patch(`/sales/${created.id}`, {
        name: 'New name',
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 15 }],
      });
      assert.equal(res.status, 409);
    });

    it('only the person who scheduled a pending campaign can edit it', async () => {
      const p = await product('EDIT-OWNER', 20);
      const created = (
        await scheduler.post('/sales', {
          name: `EditOwner ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      const res = await scheduler2.patch(`/sales/${created.id}`, {
        name: 'Hijacked',
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
      });
      assert.equal(res.status, 403);
    });

    it('editing a pending campaign replaces its terms in place, status unchanged', async () => {
      const p = await product('EDIT-HAPPY', 20);
      const created = (
        await scheduler.post('/sales', {
          name: `EditHappy ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      const res = await scheduler.patch(`/sales/${created.id}`, {
        name: `EditHappy Renamed ${run}`,
        startsAt: future(1),
        endsAt: future(3),
        products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 25 }],
      });
      assert.equal(res.status, 200);
      assert.equal(res.json.status, 'PENDING_APPROVAL');
      assert.equal(res.json.name, `EditHappy Renamed ${run}`);
      assert.equal(Number(res.json.products[0].discountValue), 25);
    });

    it('editing re-checks the one-campaign-per-product overlap rule', async () => {
      const pA = await product('EDIT-OV-A', 20);
      const pB = await product('EDIT-OV-B', 20);
      const campaignA = (
        await scheduler.post('/sales', {
          name: `OverlapA ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: pA.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await scheduler.post('/sales', {
        name: `OverlapB ${run}`,
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: pB.id, discountType: 'PERCENT', discountValue: 10 }],
      });
      const res = await scheduler.patch(`/sales/${campaignA.id}`, {
        name: `OverlapA ${run}`,
        startsAt: future(1),
        endsAt: future(2),
        products: [{ productId: pB.id, discountType: 'PERCENT', discountValue: 10 }], // pB already claimed
      });
      assert.equal(res.status, 409);
    });

    it("reopen is refused while still PENDING_APPROVAL — that's what edit is for", async () => {
      const p = await product('REOPEN-PENDING', 20);
      const created = (
        await scheduler.post('/sales', {
          name: `ReopenPending ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      assert.equal((await scheduler.post(`/sales/${created.id}/reopen`, {})).status, 409);
    });

    for (const path of ['SCHEDULED', 'ACTIVE', 'ENDED', 'REJECTED', 'CANCELLED']) {
      it(`reopen brings a ${path} campaign back to PENDING_APPROVAL, and separation of duties applies again`, async () => {
        const p = await product(`REOPEN-${path}`, 40);
        const created = (
          await scheduler.post('/sales', {
            name: `Reopen${path} ${run}`,
            startsAt: future(1),
            endsAt: future(2),
            products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
          })
        ).json;

        if (path === 'SCHEDULED') {
          await approver.post(`/sales/${created.id}/approve`, {});
        } else if (path === 'ACTIVE') {
          await approver.post(`/sales/${created.id}/approve`, {});
          await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), created.id]);
          await tick();
        } else if (path === 'ENDED') {
          await approver.post(`/sales/${created.id}/approve`, {});
          await app.db.exec('UPDATE sale_campaigns SET starts_at = ?, ends_at = ? WHERE id = ?', [new Date(past(2000)), new Date(past()), created.id]);
          // Starting and ending are mutually exclusive within one tick — backdated past both
          // boundaries needs two ticks: SCHEDULED -> ACTIVE, then ACTIVE -> ENDED.
          await tick();
          await tick();
        } else if (path === 'REJECTED') {
          await approver.post(`/sales/${created.id}/reject`, { reviewNote: 'not now' });
        } else if (path === 'CANCELLED') {
          await approver.post(`/sales/${created.id}/approve`, {});
          await approver.post(`/sales/${created.id}/cancel`, { reviewNote: 'changed plans' });
        }
        assert.equal((await api.get(`/sales/${created.id}`)).json.status, path);

        const reopened = await scheduler.post(`/sales/${created.id}/reopen`, {});
        assert.equal(reopened.status, 201);
        assert.equal(reopened.json.status, 'PENDING_APPROVAL');
        assert.equal(reopened.json.requestedByUser.email.startsWith('scheduler-'), true);

        if (path === 'ACTIVE') {
          // Pulled off sale immediately — left ACTIVE the moment it reopened, pending re-approval.
          assert.equal((await api.get(`/products/${p.id}`)).json.sale, undefined);
        }

        // Separation of duties re-applies: the reopener cannot also approve it.
        assert.equal((await scheduler.post(`/sales/${created.id}/approve`, {})).status, 403);
        const approved = await approver2.post(`/sales/${created.id}/approve`, { reviewNote: 'ok again' });
        assert.equal(approved.status, 201);
      });
    }

    it('reopen can replace the terms at the same time', async () => {
      const p = await product('REOPEN-TERMS', 40);
      const created = (
        await scheduler.post('/sales', {
          name: `ReopenTerms ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/reject`, { reviewNote: 'no' });

      const res = await scheduler.post(`/sales/${created.id}/reopen`, {
        name: `ReopenTerms Fixed ${run}`,
        startsAt: future(1),
        endsAt: future(4),
        products: [{ productId: p.id, discountType: 'FIXED_PRICE', discountValue: 33 }],
      });
      assert.equal(res.status, 201);
      assert.equal(res.json.status, 'PENDING_APPROVAL');
      assert.equal(res.json.name, `ReopenTerms Fixed ${run}`);
      assert.equal(res.json.products[0].discountType, 'FIXED_PRICE');
      assert.equal(Number(res.json.products[0].discountValue), 33);
    });
  });

  describe('daily time-of-day window', () => {
    // UTC-of-day (daily_window_start/end's own convention — see schema.sql), NOT local wall-clock
    // time: CURTIME() runs under this pool's time_zone '+00:00' session (core/db.js), so it's UTC.
    const timeAt = (offsetMinutes) => new Date(Date.now() + offsetMinutes * 60_000).toISOString().slice(11, 19);

    it('both-or-neither: setting only one of the two window fields is rejected', async () => {
      const p = await product('WIN-BADPAIR', 10);
      const res = await scheduler.post('/sales', {
        name: `WinBadPair ${run}`,
        startsAt: future(1),
        endsAt: future(5),
        dailyWindowStart: '15:00:00',
        products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
      });
      assert.equal(res.status, 400);
    });

    it('a SCHEDULED daily-window campaign starts only once CURTIME() is inside the window', async () => {
      const p = await product('WIN-START', 10);
      const created = (
        await scheduler.post('/sales', {
          name: `WinStart ${run}`,
          startsAt: future(1),
          endsAt: future(5),
          dailyWindowStart: timeAt(-60),
          dailyWindowEnd: timeAt(-30), // window already closed for today
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/approve`, {});
      await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), created.id]);

      // Outside the window: tick must NOT start it.
      let res = await tick();
      assert.equal(res.json().started, 0);
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'SCHEDULED');

      // Widen the window to cover now: tick must start it.
      await app.db.exec('UPDATE sale_campaigns SET daily_window_start = ?, daily_window_end = ? WHERE id = ?', [timeAt(-60), timeAt(60), created.id]);
      res = await tick();
      assert.equal(res.json().started, 1);
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'ACTIVE');
    });

    it('an ACTIVE daily-window campaign pauses to SCHEDULED (not ENDED) when the window closes but endsAt has not passed', async () => {
      const p = await product('WIN-PAUSE', 10);
      const created = (
        await scheduler.post('/sales', {
          name: `WinPause ${run}`,
          startsAt: future(1),
          endsAt: future(5),
          dailyWindowStart: timeAt(-60),
          dailyWindowEnd: timeAt(60),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/approve`, {});
      await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), created.id]);
      await tick();
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'ACTIVE');

      // Close today's window (endsAt is still 5 days out).
      await app.db.exec('UPDATE sale_campaigns SET daily_window_end = ? WHERE id = ?', [timeAt(-1), created.id]);
      const res = await tick();
      assert.equal(res.json().paused, 1);
      assert.equal(res.json().ended, 0);
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'SCHEDULED');
      assert.equal((await api.get(`/products/${p.id}`)).json.sale, undefined); // off sale while paused
    });

    it('a true ends_at pass always wins and goes ENDED, even while the daily window is still open', async () => {
      const p = await product('WIN-TRUEEND', 10);
      const created = (
        await scheduler.post('/sales', {
          name: `WinTrueEnd ${run}`,
          startsAt: future(1),
          endsAt: future(5),
          dailyWindowStart: timeAt(-60),
          dailyWindowEnd: timeAt(60), // open right now, and stays open
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/approve`, {});
      await app.db.exec('UPDATE sale_campaigns SET starts_at = ?, ends_at = ? WHERE id = ?', [new Date(past(2000)), new Date(past()), created.id]);

      // Starting and ending are mutually exclusive within one tick (ending only matches rows already
      // ACTIVE) — a row backdated past both boundaries needs two ticks: starts on the first...
      const res1 = await tick();
      assert.equal(res1.json().started, 1);
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'ACTIVE');
      // ...and the true end wins over the still-open window on the second.
      const res2 = await tick();
      assert.equal(res2.json().ended, 1);
      assert.equal(res2.json().paused, 0);
      assert.equal((await api.get(`/sales/${created.id}`)).json.status, 'ENDED');
    });
  });

  describe('per-customer usage cap', () => {
    it('max_uses_per_customer round-trips through create and edit, and appears once active', async () => {
      const p = await product('CAP-ROUNDTRIP', 40);
      const created = (
        await scheduler.post('/sales', {
          name: `CapRoundtrip ${run}`,
          startsAt: future(1),
          endsAt: future(8),
          maxUsesPerCustomer: 2,
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      assert.equal(created.maxUsesPerCustomer, 2);

      const edited = (
        await scheduler.patch(`/sales/${created.id}`, {
          name: created.name,
          startsAt: created.startsAt,
          endsAt: created.endsAt,
          maxUsesPerCustomer: 5,
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      assert.equal(edited.maxUsesPerCustomer, 5);

      await approver.post(`/sales/${created.id}/approve`, {});
      await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), created.id]);
      await tick();

      const withSale = (await api.get(`/products/${p.id}`)).json;
      assert.equal(withSale.sale.maxUsesPerCustomer, 5);
    });

    it('left out, max_uses_per_customer stays unlimited (undefined on the attached sale block, not 0)', async () => {
      const p = await product('CAP-UNLIMITED', 40);
      const created = (
        await scheduler.post('/sales', {
          name: `CapUnlimited ${run}`,
          startsAt: future(1),
          endsAt: future(8),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      assert.equal(created.maxUsesPerCustomer, null);
      await approver.post(`/sales/${created.id}/approve`, {});
      await app.db.exec('UPDATE sale_campaigns SET starts_at = ? WHERE id = ?', [new Date(past()), created.id]);
      await tick();
      const withSale = (await api.get(`/products/${p.id}`)).json;
      assert.equal(withSale.sale.maxUsesPerCustomer, undefined);
    });

    it('reopening can clear the cap back to unlimited', async () => {
      const p = await product('CAP-REOPEN-CLEAR', 40);
      const created = (
        await scheduler.post('/sales', {
          name: `CapReopenClear ${run}`,
          startsAt: future(1),
          endsAt: future(2),
          maxUsesPerCustomer: 1,
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }],
        })
      ).json;
      await approver.post(`/sales/${created.id}/reject`, { reviewNote: 'so it can be reopened' });
      const reopened = (
        await scheduler.post(`/sales/${created.id}/reopen`, {
          name: created.name,
          startsAt: future(1),
          endsAt: future(2),
          products: [{ productId: p.id, discountType: 'PERCENT', discountValue: 10 }], // maxUsesPerCustomer omitted
        })
      ).json;
      assert.equal(reopened.maxUsesPerCustomer, null);
    });
  });
});
