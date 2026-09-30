'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createFakeWarehouse, createTestApp, client, loginAs, uid, settle } = require('./helpers');
const { totp } = require('../src/core/crypto');

const SOAP = '11111111-1111-4111-8111-111111111111'; // E 12.50 in the fake warehouse

/** Shared fixtures: an app, an admin client, a customer, and helpers for users with given roles. */
async function setup(configOverrides = {}) {
  const warehouse = await createFakeWarehouse();
  const app = await createTestApp({ warehouseApi: { url: warehouse.url, key: 'test-key' }, ...configOverrides });
  const admin = await loginAs(app.origin);
  const api = client(app.origin, admin.accessToken);
  const customer = (await api.post('/customers', { name: `Cust ${uid()}` })).json;
  const roles = (await api.get('/roles')).json;
  const roleId = (name) => roles.find((r) => r.name === name).id;

  async function makeUser(roleName, extra = {}) {
    const email = `u-${uid()}@test.local`;
    const created = await api.post('/users', { email, password: 'Passw0rd!x', fullName: `${roleName} ${uid()}`, roleIds: [roleId(roleName)], ...extra });
    assert.equal(created.status, 201, created.body);
    const session = await loginAs(app.origin, { email, password: 'Passw0rd!x' });
    return { ...created.json, email, c: client(app.origin, session.accessToken) };
  }

  /** An order owned by `owner` (a client), taken to PENDING_APPROVAL then APPROVED by admin. */
  async function approvedOrder(owner = api, qty = 4, headers) {
    const order = (await owner.post('/orders', { customerId: customer.id, items: [{ productId: SOAP, quantity: qty }] })).json;
    await owner.post(`/orders/${order.id}/submit`, {});
    const res = await api.post(`/orders/${order.id}/approve`, {}, headers?.(order.id));
    assert.equal(res.status, 201, res.body);
    return res.json;
  }

  return {
    warehouse,
    app,
    admin,
    api,
    customer,
    makeUser,
    approvedOrder,
    close: async () => {
      await app.close();
      await warehouse.close();
    },
  };
}

/** Requests a code by email for (action, targetId) and returns the X-OTP headers carrying it. */
async function otpHeaders(app, c, email, action, targetId) {
  const before = app.outbox.length;
  const challenge = await c.post('/auth/otp', { action, targetId, channel: 'EMAIL' });
  assert.equal(challenge.status, 201, challenge.body);
  const message = app.outbox.slice(before).find((m) => m.to === email);
  const code = message.text.match(/\b(\d{6})\b/)[1];
  return { 'x-otp-challenge': challenge.json.challengeId, 'x-otp-code': code };
}

describe('payments', () => {
  let fx;
  before(async () => {
    fx = await setup();
  });
  after(() => fx.close());

  it('refuses payments on a draft; records partial then full payment, deriving payment status', async () => {
    const draft = (await fx.api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 4 }] })).json;
    const onDraft = await fx.api.post('/payments', { orderId: draft.id, amount: 10, method: 'CASH' });
    assert.equal(onDraft.status, 409);
    assert.match(onDraft.json.message, /DRAFT order/);

    const order = await fx.approvedOrder(); // total E 50
    const first = await fx.api.post('/payments', { orderId: order.id, amount: 20, method: 'CASH', notes: 'deposit' });
    assert.equal(first.status, 201, first.body);
    assert.equal(first.json.paymentStatus, 'PARTIAL');
    assert.equal(first.json.amountPaid, 20);
    assert.equal(first.json.balanceDue, 30);
    assert.equal(first.json.payment.method, 'CASH');
    assert.equal(first.json.payment.recordedByUser.fullName, 'System Administrator');

    const read = (await fx.api.get(`/orders/${order.id}`)).json;
    assert.equal(read.paymentStatus, 'PARTIAL');
    assert.equal(read.amountPaid, '20');
    assert.equal(read.status, 'APPROVED', 'payment never moves the order lifecycle (rule 6)');

    const rest = await fx.api.post('/payments', { orderId: order.id, amount: 30, method: 'MOBILE_MONEY', reference: 'MP240929.1234' });
    assert.equal(rest.json.paymentStatus, 'PAID');
    assert.equal(rest.json.balanceDue, 0);

    // The all-payments ledger (reports.view) names the order and its customer on each row.
    const ledger = (await fx.api.get('/payments')).json.filter((p) => p.order.id === order.id);
    assert.equal(ledger.length, 2);
    assert.equal(ledger[0].order.orderNumber, order.orderNumber);
    assert.equal(ledger[0].customer.id, order.customerId);
    assert.ok(ledger[0].customer.name);

    const more = await fx.api.post('/payments', { orderId: order.id, amount: 1, method: 'CASH' });
    assert.equal(more.status, 409);
    assert.match(more.json.message, /already fully paid/);
  });

  it('refuses overpayment, a missing reference for non-cash, bad amounts and future dates', async () => {
    const order = await fx.approvedOrder(fx.api, 2); // E 25
    const over = await fx.api.post('/payments', { orderId: order.id, amount: 25.01, method: 'CASH' });
    assert.equal(over.status, 409);
    assert.equal(over.json.balanceDue, 25);
    assert.match(over.json.message, /overpayment is not allowed/);

    const noRef = await fx.api.post('/payments', { orderId: order.id, amount: 5, method: 'BANK_TRANSFER', reference: '   ' });
    assert.equal(noRef.status, 400);
    assert.match(noRef.json.message, /reference/);

    assert.equal((await fx.api.post('/payments', { orderId: order.id, amount: 0, method: 'CASH' })).status, 400);
    assert.equal((await fx.api.post('/payments', { orderId: order.id, amount: 1.005, method: 'CASH' })).status, 400, 'no fractions of a cent');
    assert.equal((await fx.api.post('/payments', { orderId: order.id, amount: 5, method: 'CHEQUE' })).status, 400);

    const future = new Date(Date.now() + 86_400_000).toISOString();
    const late = await fx.api.post('/payments', { orderId: order.id, amount: 5, method: 'CASH', paidAt: future });
    assert.equal(late.status, 400);
    assert.match(late.json.message, /future/);
  });

  it('two payments racing for the same balance cannot both land (row lock on the order)', async () => {
    const order = await fx.approvedOrder(fx.api, 2); // E 25
    const results = await Promise.all(
      [1, 2, 3].map(() => fx.api.post('/payments', { orderId: order.id, amount: 25, method: 'CASH' })),
    );
    assert.deepEqual(results.map((r) => r.status).sort(), [201, 409, 409]);
    assert.equal((await fx.api.get(`/payments?orderId=${order.id}`)).json.amountPaid, 25);
  });

  it('voids a payment (kept on record with who/why), re-deriving the status; never twice', async () => {
    const order = await fx.approvedOrder(fx.api, 2); // E 25
    const paid = (await fx.api.post('/payments', { orderId: order.id, amount: 25, method: 'CARD', reference: 'SLIP-77' })).json;
    assert.equal(paid.paymentStatus, 'PAID');

    assert.equal((await fx.api.post(`/payments/${paid.payment.id}/void`, { reason: '' })).status, 400);
    const voided = await fx.api.post(`/payments/${paid.payment.id}/void`, { reason: 'Card declined afterwards' });
    assert.equal(voided.status, 200, voided.body);
    assert.equal(voided.json.payment.status, 'VOIDED');
    assert.equal(voided.json.payment.voidReason, 'Card declined afterwards');
    assert.equal(voided.json.payment.voidedByUser.fullName, 'System Administrator');
    assert.equal(voided.json.paymentStatus, 'UNPAID');

    const again = await fx.api.post(`/payments/${paid.payment.id}/void`, { reason: 'again' });
    assert.equal(again.status, 409);

    const list = (await fx.api.get(`/payments?orderId=${order.id}`)).json;
    assert.equal(list.payments.length, 1, 'a voided payment stays on record');
    assert.equal(list.amountPaid, 0);
  });

  it('an order with money on it cannot be cancelled until its payments are voided', async () => {
    const order = await fx.approvedOrder(fx.api, 2);
    const p = (await fx.api.post('/payments', { orderId: order.id, amount: 10, method: 'CASH' })).json;
    const blocked = await fx.api.post(`/orders/${order.id}/cancel`, { note: 'customer changed mind' });
    assert.equal(blocked.status, 409);
    assert.match(blocked.json.message, /void them before cancelling/);
    await fx.api.post(`/payments/${p.payment.id}/void`, { reason: 'Refunded in cash' });
    assert.equal((await fx.api.post(`/orders/${order.id}/cancel`, { note: 'customer changed mind' })).status, 201);
  });

  it('is permission-gated, and a consultant only sees payments on their own orders', async () => {
    const consultant = await fx.makeUser('CONSULTANT');
    const other = await fx.makeUser('CONSULTANT');
    const mine = await fx.approvedOrder(consultant.c, 2);

    assert.equal((await consultant.c.post('/payments', { orderId: mine.id, amount: 5, method: 'CASH' })).status, 403);
    assert.equal((await fx.api.post('/payments', { orderId: mine.id, amount: 5, method: 'CASH' })).status, 201);

    assert.equal((await consultant.c.get(`/payments?orderId=${mine.id}`)).json.amountPaid, 5);
    assert.equal((await other.c.get(`/payments?orderId=${mine.id}`)).status, 404, "another consultant's order is not found");
    assert.equal((await consultant.c.get('/payments')).status, 403, 'the all-payments listing is for reports.view');
  });

  it('reports money in by method, voids, and what is still owed; the dashboard summarises it', async () => {
    const report = await fx.api.get('/reports/payments');
    assert.equal(report.status, 200);
    const { collected, voided, outstanding } = report.json;
    const sum = (rows) => Math.round(rows.reduce((s, r) => s + r.amount, 0) * 100) / 100;
    assert.equal(collected.amount, sum(collected.byMethod));
    assert.ok(collected.byMethod.some((m) => m.method === 'MOBILE_MONEY'));
    assert.ok(voided.count >= 2);
    assert.ok(outstanding.orders.every((o) => o.balanceDue > 0 && !['DRAFT', 'REJECTED', 'CANCELLED'].includes(o.status)));
    assert.equal(outstanding.amount, Math.round(outstanding.orders.reduce((s, o) => s + o.balanceDue, 0) * 100) / 100);

    // Cross-check the collected total against an independent query.
    const [{ total }] = await fx.app.db.query("SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE status = 'RECORDED'");
    assert.equal(collected.amount, Number(total));

    const dash = (await fx.api.get('/dashboard')).json;
    assert.equal(dash.outstanding.amount, outstanding.amount);
    assert.ok(dash.today.collected > 0);
    assert.ok(Array.isArray(dash.recentOrders) && dash.recentOrders.length > 0);
    assert.equal(typeof dash.awaitingApproval, 'number');
  });
});

describe('one-time codes, MFA, notifications and delivery settings', () => {
  let fx;
  before(async () => {
    // A high code allowance: the rate limit is per user over 10 minutes, and repeated test runs reuse the admin.
    fx = await setup({ otp: { enabled: true, maxPerWindow: 1000 } });
  });
  after(() => fx.close());

  const adminEmail = 'admin@test.local';

  it('approve without a code answers 428; a code bound to that order confirms it once', async () => {
    const order = (await fx.api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
    await fx.api.post(`/orders/${order.id}/submit`, {});

    const bare = await fx.api.post(`/orders/${order.id}/approve`, {});
    assert.equal(bare.status, 428);
    assert.equal(bare.json.otpRequired, true);
    assert.equal(bare.json.action, 'order.approve');
    assert.equal(bare.json.targetId, order.id);
    assert.deepEqual(bare.json.availableChannels, ['EMAIL']);

    const otherOrder = (await fx.api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
    const wrongTarget = await otpHeaders(fx.app, fx.api, adminEmail, 'order.approve', otherOrder.id);
    assert.equal((await fx.api.post(`/orders/${order.id}/approve`, {}, wrongTarget)).status, 403, 'a code is bound to its order');

    const headers = await otpHeaders(fx.app, fx.api, adminEmail, 'order.approve', order.id);
    const codeEmail = fx.app.outbox.at(-1);
    assert.match(codeEmail.html, /^<!DOCTYPE html>/, 'codes arrive as the branded HTML email');
    assert.match(codeEmail.subject, /is your code to approve an order/);

    const ok = await fx.api.post(`/orders/${order.id}/approve`, {}, headers);
    assert.equal(ok.status, 201, ok.body);
    assert.equal(ok.json.status, 'APPROVED');
    const reused = await fx.api.post(`/orders/${order.id}/reject`, { note: 'x' }, headers);
    assert.equal(reused.status, 403, 'single use, and bound to its action');
  });

  it('protects payment voids, order cancels, and customer/user deactivation', async () => {
    const o = (await fx.api.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 1 }] })).json;
    await fx.api.post(`/orders/${o.id}/submit`, {});
    await fx.api.post(`/orders/${o.id}/approve`, {}, await otpHeaders(fx.app, fx.api, adminEmail, 'order.approve', o.id));
    const p = (await fx.api.post('/payments', { orderId: o.id, amount: 5, method: 'CASH' })).json;

    assert.equal((await fx.api.post(`/payments/${p.payment.id}/void`, { reason: 'typo' })).status, 428);
    const voided = await fx.api.post(
      `/payments/${p.payment.id}/void`,
      { reason: 'typo' },
      await otpHeaders(fx.app, fx.api, adminEmail, 'payment.void', p.payment.id),
    );
    assert.equal(voided.status, 200, voided.body);

    assert.equal((await fx.api.post(`/orders/${o.id}/cancel`, {})).status, 428);

    const cust = (await fx.api.post('/customers', { name: `Temp ${uid()}` })).json;
    assert.equal((await fx.api.patch(`/customers/${cust.id}`, { notes: 'fine' })).status, 200, 'an ordinary edit needs no code');
    assert.equal((await fx.api.patch(`/customers/${cust.id}`, { status: 'INACTIVE' })).status, 428);
    assert.equal((await fx.api.delete(`/customers/${cust.id}`)).status, 428);

    const user = await fx.makeUser('WAREHOUSE');
    assert.equal((await fx.api.patch(`/users/${user.id}`, { status: 'SUSPENDED' })).status, 428);
    assert.equal((await fx.api.delete(`/users/${user.id}`)).status, 428);
  });

  it('sign-in MFA by email: password, then a code, then tokens', async () => {
    const user = await fx.makeUser('CONSULTANT');
    const setup = await user.c.post('/auth/mfa/setup', { method: 'EMAIL' });
    assert.equal(setup.status, 200, setup.body);
    const setupCode = fx.app.outbox.at(-1).text.match(/\b(\d{6})\b/)[1];
    const confirmed = await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.json.challengeId, code: setupCode });
    assert.equal(confirmed.json.mfaMethod, 'EMAIL');

    const login = await client(fx.app.origin).post('/auth/login', { email: user.email, password: 'Passw0rd!x' });
    assert.equal(login.status, 200);
    assert.equal(login.json.mfaRequired, true);
    assert.equal(login.json.accessToken, undefined, 'no tokens before the second step');
    const code = fx.app.outbox.at(-1).text.match(/\b(\d{6})\b/)[1];
    assert.equal((await client(fx.app.origin).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code: '000000' })).status, 403);
    const verified = await client(fx.app.origin).post('/auth/mfa/verify', { challengeId: login.json.challengeId, code });
    assert.equal(verified.status, 200, verified.body);
    assert.ok(verified.json.accessToken);

    const me = (await user.c.get('/auth/me')).json;
    assert.equal(me.mfaMethod, 'EMAIL');
  });

  it('authenticator-app MFA: enrol with a TOTP code; turning it off needs a code; admins can reset it', async () => {
    const user = await fx.makeUser('CONSULTANT');
    const setup = (await user.c.post('/auth/mfa/setup', { method: 'TOTP' })).json;
    assert.match(setup.otpauthUrl, /^otpauth:\/\/totp\/Ordering%20System/);
    const confirmed = await user.c.post('/auth/mfa/setup/confirm', { challengeId: setup.challengeId, code: totp(setup.secret) });
    assert.equal(confirmed.json.mfaMethod, 'TOTP');

    const login = (await client(fx.app.origin).post('/auth/login', { email: user.email, password: 'Passw0rd!x' })).json;
    assert.deepEqual(login.availableChannels, ['TOTP']);
    const session = await client(fx.app.origin).post('/auth/mfa/verify', { challengeId: login.challengeId, code: totp(setup.secret) });
    assert.equal(session.status, 200);

    assert.equal((await user.c.post('/auth/mfa/disable', {})).status, 428);
    const reset = await fx.api.post(`/users/${user.id}/mfa/reset`, {});
    assert.equal(reset.json.mfaMethod, 'NONE');
    assert.ok(!('totpSecret' in reset.json), 'the secret never leaves the server');
  });

  it('users carry a phone (E.164) and a notification channel; SMS needs a phone', async () => {
    const user = await fx.makeUser('CONSULTANT', { phone: '+268 7612 3456', notifyChannel: 'SMS' });
    assert.equal(user.phone, '+26876123456');
    assert.equal((await fx.api.post('/users', { email: `x-${uid()}@test.local`, password: 'Passw0rd!x', fullName: 'X', notifyChannel: 'SMS' })).status, 400);
    assert.equal((await user.c.patch('/users/me', { phone: '0761' })).status, 400);
    const me = await user.c.patch('/users/me', { notifyChannel: 'EMAIL' });
    assert.equal(me.json.notifyChannel, 'EMAIL');
  });

  it('notifies approvers of a submitted order, and the consultant of the outcome', async () => {
    const approver = await fx.makeUser('MANAGER', { phone: '+26870000100', notifyChannel: 'SMS' });
    const consultant = await fx.makeUser('CONSULTANT');
    const order = (await consultant.c.post('/orders', { customerId: fx.customer.id, items: [{ productId: SOAP, quantity: 2 }] })).json;
    await consultant.c.post(`/orders/${order.id}/submit`, {});
    await settle();
    const sms = fx.app.outbox.find((m) => m.to === '+26870000100' && m.text.includes(order.orderNumber));
    assert.ok(sms, 'the approver gets an SMS (their chosen channel)');
    assert.ok(!fx.app.outbox.some((m) => m.to === consultant.email && /awaiting/.test(m.text)), 'the submitter is not asked to approve');

    const headers = await otpHeaders(fx.app, fx.api, adminEmail, 'order.reject', order.id);
    await fx.api.post(`/orders/${order.id}/reject`, { note: 'Price list <b>outdated</b>' }, headers);
    await settle();
    const outcome = fx.app.outbox.find((m) => m.to === consultant.email && m.subject?.includes(`${order.orderNumber} rejected`));
    assert.ok(outcome, 'the consultant hears the outcome');
    assert.match(outcome.html, /Price list &lt;b&gt;outdated&lt;\/b&gt;/, 'user text is escaped in the HTML');
    assert.ok(approver.id);
  });

  it('delivery settings: admin-only, secrets never returned, test send goes out', async () => {
    const consultant = await fx.makeUser('CONSULTANT');
    assert.equal((await consultant.c.get('/settings/delivery')).status, 403);

    const saved = await fx.api.put('/settings/delivery', {
      email: { host: 'smtp.example.com', port: 587, user: 'orders@example.com', pass: 's3cret', from: 'orders@example.com' },
    });
    assert.equal(saved.status, 200, saved.body);
    assert.equal(saved.json.email.hasPassword, true);
    assert.ok(!JSON.stringify(saved.json).includes('s3cret'));
    const [row] = await fx.app.db.query("SELECT value FROM app_settings WHERE `key` = 'email.pass'");
    assert.ok(row.value && !row.value.includes('s3cret'), 'stored encrypted');
    const [audit] = await fx.app.db.query("SELECT new_value AS v FROM audit_logs WHERE entity = 'app_settings' ORDER BY created_at DESC LIMIT 1");
    assert.ok(!String(audit.v).includes('s3cret'), 'never in the audit trail');

    const sent = await fx.api.post('/settings/delivery/test', { channel: 'EMAIL', to: 'someone@example.com' });
    assert.equal(sent.json.ok, true);
    assert.match(fx.app.outbox.at(-1).html, /Email delivery is working/);
  });

  it('CORS lets the browser send the one-time-code headers', async () => {
    const res = await fetch(`${fx.app.origin}/orders/x/approve`, {
      method: 'OPTIONS',
      headers: { origin: 'http://localhost:8080', 'access-control-request-method': 'POST', 'access-control-request-headers': 'x-otp-challenge,x-otp-code' },
    });
    assert.match(res.headers.get('access-control-allow-headers') ?? '', /X-OTP-Challenge/i);
  });
});
