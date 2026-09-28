'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createTestApp, client, loginAs, uid, settle } = require('./helpers');
const { totp } = require('../src/core/crypto');

/**
 * Warehouse access control (deny by default), one-time-code confirmation of sensitive actions,
 * sign-in MFA (email / SMS / authenticator app) and approval notifications. Runs with OTP ON;
 * every email/SMS lands in `app.outbox` so the tests can read the codes a user would receive.
 */
describe('access control, one-time codes, MFA and notifications', () => {
  let app;
  let api; // admin (holds warehouse.access.all)
  const run = uid();
  const fx = {};

  /** The newest 6-digit code sent to `to` (email address or phone number). */
  const lastCodeFor = (to) => {
    const message = [...app.outbox].reverse().find((m) => m.to === to && /\b\d{6}\b/.test(m.text));
    assert.ok(message, `no code was sent to ${to}`);
    return message.text.match(/\b(\d{6})\b/)[1];
  };

  /** Requests a step-up code for (action, targetId) as `c`, and returns the headers that confirm it. */
  async function otpHeaders(c, to, action, targetId, channel = 'EMAIL') {
    const res = await c.post('/auth/otp', { action, targetId, channel });
    assert.equal(res.status, 201, res.body);
    return { 'x-otp-challenge': res.json.challengeId, 'x-otp-code': lastCodeFor(to) };
  }

  /** Creates a user holding `permissionKeys` (via a fresh role) and signs them in. */
  async function makeUser(permissionKeys, extra = {}) {
    const perms = (await api.get('/permissions')).json;
    const role = (await api.post('/roles', { name: `R-${uid()}` })).json;
    await api.put(`/roles/${role.id}/permissions`, {
      permissionIds: perms.filter((p) => permissionKeys.includes(p.key)).map((p) => p.id),
    });
    const email = `u-${uid()}@test.local`;
    const password = 'Passw0rd!x';
    const user = (await api.post('/users', { email, password, fullName: `User ${uid()}`, roleIds: [role.id], ...extra })).json;
    const session = await loginAs(app, { email, password });
    return { ...user, email, password, c: client(app, { token: session.accessToken }) };
  }

  before(async () => {
    app = await createTestApp({ otp: { enabled: true, maxPerWindow: 1000 } });
    const admin = await loginAs(app);
    fx.adminEmail = admin.user.email;
    api = client(app, { token: admin.accessToken });

    const mkWarehouse = async (tag) => {
      const warehouse = (await api.post('/warehouses', { name: `WH ${tag} ${run}`, code: `WH${tag}-${run}` })).json;
      const bin = (await api.post('/locations', { warehouseId: warehouse.id, name: `Bin ${tag}`, code: `B${tag}-${run}`, locationType: 'BIN' })).json;
      const workstream = (await api.post('/workstreams', { warehouseId: warehouse.id, name: `WS ${tag} ${run}`, code: `WS${tag}-${run}` })).json;
      const category = (await api.post('/categories', { name: `Cat ${tag} ${run}`, workstreamId: workstream.id })).json;
      const product = (
        await api.post('/products', { sku: `SKU${tag}-${run}`, name: `Prod ${tag}`, categoryId: category.id, sellingPrice: 5, costPrice: 2, uom: 'EACH' })
      ).json;
      await api.post('/inventory/receiving', { supplier: 'S', productId: product.id, quantity: 50, toLocationId: bin.id });
      return { warehouse, bin, workstream, category, product };
    };
    fx.a = await mkWarehouse('A');
    fx.b = await mkWarehouse('B');
  });

  after(async () => {
    await app.close();
  });

  describe('warehouse access (deny by default)', () => {
    let staff;

    before(async () => {
      staff = await makeUser(['catalogue.view', 'warehouse.structure.view', 'inventory.view', 'inventory.receive', 'reports.view']);
    });

    it('a user with no warehouse assignment sees nothing warehouse-owned', async () => {
      assert.deepEqual((await staff.c.get('/warehouses')).json, []);
      assert.deepEqual((await staff.c.get('/locations')).json, []);
      assert.deepEqual((await staff.c.get('/products')).json, []);
      assert.deepEqual((await staff.c.get('/inventory/balances')).json, []);
      assert.equal((await staff.c.get(`/warehouses/${fx.a.warehouse.id}`)).status, 403);
      assert.equal((await staff.c.get(`/products/${fx.a.product.id}`)).status, 403);
      const dashboard = (await staff.c.get('/dashboard')).json;
      assert.equal(dashboard.catalogue.activeWarehouseCount, 0);
      assert.equal(dashboard.catalogue.activeProductCount, 0);
    });

    it('assigning one warehouse opens exactly that warehouse', async () => {
      const res = await api.put(`/users/${staff.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      assert.equal(res.status, 200);
      assert.deepEqual(res.json.warehouses.map((w) => w.id), [fx.a.warehouse.id]);

      assert.deepEqual((await staff.c.get('/warehouses')).json.map((w) => w.id), [fx.a.warehouse.id]);
      const products = (await staff.c.get('/products')).json.map((p) => p.id);
      assert.ok(products.includes(fx.a.product.id));
      assert.ok(!products.includes(fx.b.product.id));
      assert.equal((await staff.c.get(`/products/${fx.b.product.id}`)).status, 403);
      assert.ok((await staff.c.get('/inventory/balances')).json.every((b) => b.location.warehouseId === fx.a.warehouse.id));
      assert.deepEqual((await staff.c.get('/users/me/warehouses')).json.map((w) => w.id), [fx.a.warehouse.id]);
    });

    it('stock operations are refused outside the assigned warehouses', async () => {
      const inside = await staff.c.post('/inventory/receiving', { supplier: 'S', productId: fx.a.product.id, quantity: 1, toLocationId: fx.a.bin.id });
      assert.equal(inside.status, 201);
      const outside = await staff.c.post('/inventory/receiving', { supplier: 'S', productId: fx.b.product.id, quantity: 1, toLocationId: fx.b.bin.id });
      assert.equal(outside.status, 403);
    });

    it('workstream manager assignments must sit inside warehouse access, and go when it goes', async () => {
      const manager = await makeUser(['catalogue.view', 'products.manage']);
      const denied = await api.post(`/workstreams/${fx.a.workstream.id}/managers`, { userId: manager.id });
      assert.equal(denied.status, 400, 'no warehouse access yet');

      await api.put(`/users/${manager.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      assert.equal((await api.post(`/workstreams/${fx.a.workstream.id}/managers`, { userId: manager.id })).status, 201);

      await api.put(`/users/${manager.id}/warehouses`, { warehouseIds: [] });
      const managers = (await api.get(`/workstreams/${fx.a.workstream.id}/managers`)).json;
      assert.ok(!managers.some((m) => m.userId === manager.id), 'losing the warehouse removes the workstream assignment');
    });

    it('assigning warehouses needs warehouse.access.assign', async () => {
      assert.equal((await staff.c.put(`/users/${staff.id}/warehouses`, { warehouseIds: [fx.b.warehouse.id] })).status, 403);
    });
  });

  describe('one-time codes confirm sensitive actions', () => {
    it('a deactivation without a code is 428 and says how to get one', async () => {
      const res = await api.delete(`/products/${fx.b.product.id}`);
      assert.equal(res.status, 428);
      assert.equal(res.json.otpRequired, true);
      assert.equal(res.json.action, 'product.deactivate');
      assert.equal(res.json.targetId, fx.b.product.id);
      assert.ok(res.json.availableChannels.includes('EMAIL'));
    });

    it('the emailed code confirms it, exactly once', async () => {
      const headers = await otpHeaders(api, fx.adminEmail, 'product.deactivate', fx.b.product.id);
      const ok = await api.delete(`/products/${fx.b.product.id}`, { headers });
      assert.equal(ok.status, 200);
      assert.equal(ok.json.status, 'INACTIVE');
      const replay = await api.delete(`/products/${fx.b.product.id}`, { headers });
      assert.equal(replay.status, 403);
      assert.equal(replay.json.otpInvalid, true);
    });

    it('a code is bound to its action AND its target', async () => {
      const headers = await otpHeaders(api, fx.adminEmail, 'product.deactivate', fx.a.product.id);
      assert.equal((await api.delete(`/categories/${fx.a.category.id}`, { headers })).status, 403, 'other action');
      const other = await otpHeaders(api, fx.adminEmail, 'location.deactivate', fx.a.bin.id);
      assert.equal((await api.delete(`/locations/${fx.b.bin.id}`, { headers: other })).status, 403, 'other target');
    });

    it('a wrong code is rejected, and the challenge locks after too many guesses', async () => {
      const res = await api.post('/auth/otp', { action: 'category.deactivate', targetId: fx.a.category.id, channel: 'EMAIL' });
      const bad = { 'x-otp-challenge': res.json.challengeId, 'x-otp-code': '000000' };
      for (let i = 0; i < 5; i++) assert.equal((await api.delete(`/categories/${fx.a.category.id}`, { headers: bad })).status, 403);
      const right = { 'x-otp-challenge': res.json.challengeId, 'x-otp-code': lastCodeFor(fx.adminEmail) };
      const locked = await api.delete(`/categories/${fx.a.category.id}`, { headers: right });
      assert.equal(locked.status, 403);
      assert.match(locked.json.message, /Too many wrong attempts/);
    });

    it('deactivating through PATCH needs a code too — even with isActive sent as the string "false"', async () => {
      const loc = (await api.post('/locations', { warehouseId: fx.a.warehouse.id, name: 'Tmp', code: `T-${uid()}`, locationType: 'BIN' })).json;
      assert.equal((await api.patch(`/locations/${loc.id}`, { isActive: 'false' })).status, 428);
      assert.equal((await api.patch(`/locations/${loc.id}`, { name: 'Renamed' })).status, 200, 'other edits need no code');
    });

    it('approving and rejecting stock adjustments need a code', async () => {
      const requester = await makeUser(['inventory.view', 'inventory.adjust.request']);
      await api.put(`/users/${requester.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      const adj = (
        await requester.c.post('/inventory/adjustments', { productId: fx.a.product.id, locationId: fx.a.bin.id, bucket: 'ON_HAND', delta: 1, direction: 'DECREASE', reason: 'test' })
      ).json;
      assert.equal((await api.post(`/inventory/adjustments/${adj.id}/approve`, {})).status, 428);
      const headers = await otpHeaders(api, fx.adminEmail, 'stock_adjustment.approve', adj.id);
      assert.equal((await api.post(`/inventory/adjustments/${adj.id}/approve`, {}, { headers })).status, 201);
    });

    it('SMS codes need a phone number, and go to it', async () => {
      const user = await makeUser(['catalogue.view']);
      assert.equal((await user.c.post('/auth/otp', { action: 'mfa.disable', channel: 'SMS' })).status, 400);
      await user.c.patch('/users/me', { phone: '+268 7612 3456' });
      const res = await user.c.post('/auth/otp', { action: 'mfa.disable', channel: 'SMS' });
      assert.equal(res.status, 201);
      assert.equal(res.json.channel, 'SMS');
      assert.ok(app.outbox.some((m) => m.channel === 'SMS' && m.to === '+26876123456'));
    });

    it('code requests are rate-limited per user (SMS costs money)', async () => {
      const limited = await createTestApp({ otp: { enabled: true, maxPerWindow: 2 } });
      try {
        const c = client(limited, { token: (await loginAs(limited)).accessToken });
        const ask = () => c.post('/auth/otp', { action: 'mfa.disable', channel: 'EMAIL' });
        // Codes this admin already requested in the last window (earlier tests) count too.
        let status;
        for (let i = 0; i < 3 && status !== 429; i++) status = (await ask()).status;
        assert.equal(status, 429);
      } finally {
        await limited.close();
      }
    });

    it('codes are never stored in the notifications table', async () => {
      const rows = await app.db.query("SELECT body FROM notifications WHERE event LIKE 'otp.%'");
      assert.ok(rows.length > 0);
      assert.ok(rows.every((r) => !/\d{6}/.test(r.body)));
    });
  });

  describe('sign-in MFA', () => {
    it('email: sign-in stops at a code, and the code finishes it', async () => {
      const user = await makeUser(['catalogue.view']);
      const setup = await user.c.post('/auth/mfa/setup', { method: 'EMAIL' });
      assert.equal(setup.status, 200);
      const confirm = await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: lastCodeFor(user.email) });
      assert.equal(confirm.json.mfaMethod, 'EMAIL');

      const login = await client(app).post('/auth/login', { email: user.email, password: user.password });
      assert.equal(login.status, 200);
      assert.equal(login.json.mfaRequired, true);
      assert.equal(login.json.accessToken, undefined, 'no tokens before the second factor');
      assert.equal(login.json.userId, undefined);

      const wrong = await client(app).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code: '000000' });
      assert.equal(wrong.status, 403);
      const done = await client(app).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code: lastCodeFor(user.email) });
      assert.equal(done.status, 200);
      assert.ok(done.json.accessToken && done.json.refreshToken);
    });

    it('an email/SMS user can switch the sign-in code to the other channel', async () => {
      const user = await makeUser(['catalogue.view'], { phone: '+26870000001' });
      const setup = await user.c.post('/auth/mfa/setup', { method: 'EMAIL' });
      await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: lastCodeFor(user.email) });

      const login = await client(app).post('/auth/login', { email: user.email, password: user.password });
      assert.deepEqual(login.json.availableChannels.sort(), ['EMAIL', 'SMS']);
      const resent = await client(app).post('/auth/mfa/resend', { challengeId: login.json.challengeId, channel: 'SMS' });
      assert.equal(resent.json.channel, 'SMS');
      const old = await client(app).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code: lastCodeFor(user.email) });
      assert.equal(old.status, 403, 'the replaced challenge is dead');
      const done = await client(app).post('/auth/mfa/verify', { challengeId: resent.json.challengeId, code: lastCodeFor('+26870000001') });
      assert.equal(done.status, 200);
    });

    it('authenticator app: enrol from the secret, sign in with the app, confirm actions with it', async () => {
      const user = await makeUser(['catalogue.view']);
      const setup = await user.c.post('/auth/mfa/setup', { method: 'TOTP' });
      assert.match(setup.json.secret, /^[A-Z2-7]{32}$/);
      assert.match(setup.json.otpauthUrl, /^otpauth:\/\/totp\//);
      const secret = setup.json.secret;

      const badConfirm = await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: '000000' });
      assert.equal(badConfirm.status, 403);
      const confirm = await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: totp(secret) });
      assert.equal(confirm.json.mfaMethod, 'TOTP');
      assert.equal((await user.c.get('/auth/me')).json.mfaMethod, 'TOTP');

      const login = await client(app).post('/auth/login', { email: user.email, password: user.password });
      assert.equal(login.json.channel, 'TOTP');
      assert.deepEqual(login.json.availableChannels, ['TOTP']);
      const done = await client(app).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code: totp(secret) });
      assert.equal(done.status, 200);

      // Turning MFA off is itself confirmed — with the app's code.
      const me = client(app, { token: done.json.accessToken });
      assert.equal((await me.post('/auth/mfa/disable', {})).status, 428);
      const challenge = (await me.post('/auth/otp', { action: 'mfa.disable', channel: 'TOTP' })).json;
      const off = await me.post('/auth/mfa/disable', {}, { headers: { 'x-otp-challenge': challenge.challengeId, 'x-otp-code': totp(secret) } });
      assert.equal(off.status, 200);
      assert.equal(off.json.mfaMethod, 'NONE');
    });

    it('an admin can reset a user who lost their device', async () => {
      const user = await makeUser(['catalogue.view']);
      const setup = await user.c.post('/auth/mfa/setup', { method: 'EMAIL' });
      await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: lastCodeFor(user.email) });
      const reset = await api.post(`/users/${user.id}/mfa/reset`, {});
      assert.equal(reset.status, 200);
      assert.equal(reset.json.mfaMethod, 'NONE');
      const login = await client(app).post('/auth/login', { email: user.email, password: user.password });
      assert.ok(login.json.accessToken);
    });
  });

  describe('contact details', () => {
    it('phone numbers are normalised to +E.164 and validated', async () => {
      const user = await makeUser(['catalogue.view']);
      assert.equal((await user.c.patch('/users/me', { phone: '(+268) 7612-0000' })).json.phone, '+26876120000');
      assert.equal((await user.c.patch('/users/me', { phone: '7612 0000' })).status, 400, 'needs a country code');
    });

    it('SMS notifications need a phone number', async () => {
      const user = await makeUser(['catalogue.view']);
      assert.equal((await user.c.patch('/users/me', { notifyChannel: 'SMS' })).status, 400);
    });
  });

  describe('packing: each person sees the items from their workstream in each open order', () => {
    it('shows only the viewer\'s lines, oldest order first, and drops the order once dispatched', async () => {
      // A second workstream in warehouse A, so one order spans two workstreams.
      const ws2 = (await api.post('/workstreams', { warehouseId: fx.a.warehouse.id, name: `WS2 ${run}`, code: `WS2-${run}` })).json;
      const cat2 = (await api.post('/categories', { name: `Cat2 ${run}`, workstreamId: ws2.id })).json;
      const prod2 = (await api.post('/products', { sku: `P2-${run}`, name: 'Second', categoryId: cat2.id, sellingPrice: 3, uom: 'EACH' })).json;
      await api.post('/inventory/receiving', { supplier: 'S', productId: prod2.id, quantity: 20, toLocationId: fx.a.bin.id });

      const key = (await api.post('/api-keys', { name: `pack-${run}`, scopes: ['stock:reserve', 'stock:issue'] })).json.rawKey;
      const reference = `order-${uid()}`;
      const reserve = await client(app).post(
        '/api/v1/stock/reserve',
        {
          reference,
          label: 'ORD-0042 · Mbabane Spar',
          lines: [
            { productId: fx.a.product.id, locationId: fx.a.bin.id, quantity: 2 },
            { productId: prod2.id, locationId: fx.a.bin.id, quantity: 3 },
          ],
        },
        { apiKey: key },
      );
      assert.equal(reserve.json.success, true, reserve.body);

      const packer = await makeUser(['packing.view', 'catalogue.view', 'products.manage']);
      await api.put(`/users/${packer.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      await api.post(`/workstreams/${ws2.id}/managers`, { userId: packer.id });

      const order = (await packer.c.get('/packing')).json.find((o) => o.reference === reference);
      assert.ok(order, 'the open order is listed');
      assert.equal(order.label, 'ORD-0042 · Mbabane Spar');
      assert.equal(order.totalLineCount, 2);
      assert.deepEqual(order.lines.map((l) => [l.product.sku, l.quantity, l.workstream.id]), [[prod2.sku, 3, ws2.id]]);

      const everyone = (await api.get('/packing')).json.find((o) => o.reference === reference);
      assert.equal(everyone.lines.length, 2, 'no workstream assignment: every line in their warehouses');

      const outsider = await makeUser(['packing.view']);
      await api.put(`/users/${outsider.id}/warehouses`, { warehouseIds: [fx.b.warehouse.id] });
      assert.ok(!(await outsider.c.get('/packing')).json.some((o) => o.reference === reference));

      await client(app).post(
        '/api/v1/stock/issue',
        { reference, lines: [{ productId: fx.a.product.id, locationId: fx.a.bin.id, quantity: 2 }, { productId: prod2.id, locationId: fx.a.bin.id, quantity: 3 }] },
        { apiKey: key },
      );
      assert.ok(!(await packer.c.get('/packing')).json.some((o) => o.reference === reference), 'dispatched orders leave the list');
    });

    it('needs packing.view', async () => {
      const user = await makeUser(['catalogue.view']);
      assert.equal((await user.c.get('/packing')).status, 403);
    });
  });

  describe('email & SMS delivery settings (set by an admin in the app)', () => {
    after(async () => {
      // Leave the shared test database's settings empty for the next run.
      await app.db.exec("DELETE FROM app_settings WHERE `key` LIKE 'email.%' OR `key` LIKE 'sms.%'");
      await app.cache.invalidate('settings');
    });

    it('saves SMTP + httpSMS details; secrets are stored encrypted and never returned', async () => {
      const res = await api.put('/settings/delivery', {
        email: { transport: 'smtp', host: 'smtp.example.test', port: 587, secure: false, user: 'mailer', pass: 'Sup3r-Secret', from: 'Warehouse <wh@example.test>' },
        sms: { transport: 'httpsms', apiKey: 'httpsms-key-123', from: '+268 7600 0000' },
      });
      assert.equal(res.status, 200, res.body);
      assert.equal(res.json.email.host, 'smtp.example.test');
      assert.equal(res.json.email.hasPassword, true);
      assert.equal(res.json.email.pass, undefined);
      assert.equal(res.json.sms.hasApiKey, true);
      assert.equal(res.json.sms.apiKey, undefined);
      assert.equal(res.json.sms.from, '+26876000000');
      assert.ok(!res.body.includes('Sup3r-Secret') && !res.body.includes('httpsms-key-123'));

      const rows = await app.db.query("SELECT `key`, value FROM app_settings WHERE `key` IN ('email.pass', 'sms.apiKey')");
      assert.equal(rows.length, 2);
      assert.ok(rows.every((r) => r.value.startsWith('v1.')), 'encrypted at rest');

      await settle();
      const audit = (await api.get('/audit-logs?entity=app_settings&pageSize=1')).json.data[0];
      assert.ok(!JSON.stringify(audit).includes('Sup3r-Secret'), 'secrets never reach the audit log');
    });

    it('a blank secret keeps the stored one; switching off real sending needs nothing else', async () => {
      const res = await api.put('/settings/delivery', { email: { host: 'smtp2.example.test', pass: '' } });
      assert.equal(res.json.email.host, 'smtp2.example.test');
      assert.equal(res.json.email.hasPassword, true);
    });

    it('refuses settings that could not work', async () => {
      const noHost = await api.put('/settings/delivery', { email: { transport: 'smtp', host: '' } });
      assert.equal(noHost.status, 400);
      const badPhone = await api.put('/settings/delivery', { sms: { transport: 'httpsms', from: '7600 0000' } });
      assert.equal(badPhone.status, 400);
    });

    it('a test message goes through the configured channel', async () => {
      const res = await api.post('/settings/delivery/test', { channel: 'SMS', to: '+26870009999' });
      assert.equal(res.status, 200);
      assert.equal(res.json.ok, true);
      assert.ok(app.outbox.some((m) => m.to === '+26870009999' && /test SMS/.test(m.text)));
    });

    it('needs settings.manage', async () => {
      const user = await makeUser(['catalogue.view']);
      assert.equal((await user.c.get('/settings/delivery')).status, 403);
      assert.equal((await user.c.put('/settings/delivery', { email: { host: 'x' } })).status, 403);
    });
  });

  describe('approval notifications', () => {
    it('approvers who can access the warehouse are told about a request; the requester hears the outcome', async () => {
      const approverIn = await makeUser(['inventory.view', 'inventory.adjust.approve'], { phone: '+26870000100', notifyChannel: 'SMS' });
      await api.put(`/users/${approverIn.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      const approverOut = await makeUser(['inventory.view', 'inventory.adjust.approve']);
      await api.put(`/users/${approverOut.id}/warehouses`, { warehouseIds: [fx.b.warehouse.id] });
      const approverMuted = await makeUser(['inventory.view', 'inventory.adjust.approve'], { notifyChannel: 'NONE' });
      await api.put(`/users/${approverMuted.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });
      const requester = await makeUser(['inventory.view', 'inventory.adjust.request']);
      await api.put(`/users/${requester.id}/warehouses`, { warehouseIds: [fx.a.warehouse.id] });

      const adj = (
        await requester.c.post('/inventory/adjustments', { productId: fx.a.product.id, locationId: fx.a.bin.id, bucket: 'ON_HAND', delta: 2, direction: 'DECREASE', reason: 'broken seal' })
      ).json;
      await settle();
      const smsToApprover = app.outbox.find((m) => m.to === '+26870000100' && /awaiting your approval/.test(m.text));
      assert.ok(smsToApprover, 'the in-warehouse approver gets an SMS (their chosen channel)');
      assert.match(smsToApprover.text, /broken seal/);
      assert.ok(!app.outbox.some((m) => m.to === approverOut.email && /awaiting/.test(m.text)), 'no access to that warehouse, no message');
      assert.ok(!app.outbox.some((m) => m.to === approverMuted.email), 'notify channel NONE opts out');

      const headers = await otpHeaders(api, fx.adminEmail, 'stock_adjustment.reject', adj.id);
      await api.post(`/inventory/adjustments/${adj.id}/reject`, { reviewNote: 'recount first <b>now</b>' }, { headers });
      await settle();
      const outcome = app.outbox.find((m) => m.to === requester.email && /was rejected/.test(m.text));
      assert.ok(outcome, 'the requester is told the outcome');
      assert.match(outcome.text, /recount first/);
      // Emails are the branded HTML template (plus the plain-text alternative), with user text escaped.
      assert.match(outcome.html, /^<!DOCTYPE html>/);
      assert.match(outcome.html, /Your stock adjustment was rejected/);
      assert.match(outcome.html, /recount first &lt;b&gt;now&lt;\/b&gt;/);
      assert.ok(!outcome.html.includes('<b>now</b>'), 'user-entered text is never raw HTML');
    });
  });
});
