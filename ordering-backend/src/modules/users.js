'use strict';

const argon2 = require('argon2');
const { badRequest, conflict, notFound, unauthorized } = require('../core/errors');
const { cols, groupBy } = require('../core/models');
const { UserStatus, NotifyChannel } = require('../core/enums');
const { obj, str, opt, arrayOf, enumOf, uuidParams } = require('../core/schema');

// The password hash and the authenticator secret never leave this service.
const USER_FIELDS = ['id', 'email', 'fullName', 'phone', 'notifyChannel', 'mfaMethod', 'status', 'createdAt', 'updatedAt'];

/**
 * Phone numbers are stored in international (E.164) form, "+26876123456" — what httpSMS needs.
 * Spaces, dashes, dots and brackets are dropped; null/'' clears the number.
 */
function normalizePhone(raw) {
  if (raw === undefined) return undefined;
  if (raw === null || String(raw).trim() === '') return null;
  const phone = String(raw).replace(/[\s().-]/g, '');
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) {
    throw badRequest('phone must be in international format with a country code, e.g. +268 7612 3456');
  }
  return phone;
}

function createUsersService({ db, models }) {
  async function withRoles(users) {
    if (users.length === 0) return users;
    const rows = await db.query(
      `SELECT ur.user_id AS userId, r.id, r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id
        WHERE ur.user_id IN (?)`,
      [users.map((u) => u.id)],
    );
    const byUser = groupBy(rows, 'userId');
    return users.map((u) => ({ ...u, roles: (byUser.get(u.id) ?? []).map(({ id, name }) => ({ id, name })) }));
  }

  const findAll = async () =>
    withRoles(await db.query(`SELECT ${cols('user', 'u', USER_FIELDS)} FROM users u ORDER BY u.created_at ASC`));

  /**
   * Active users who can actually place an order (hold `orders.create`, through any role) — the
   * definition of "a consultant" for picking purposes (customer assignment, sale-campaign
   * eligibility). Permission-based, not a role-name match (rule 1 — roles are admin-configurable
   * data, a role could be renamed or restructured and this must still mean the same thing).
   */
  const findConsultants = () =>
    db.query(
      `SELECT DISTINCT ${cols('user', 'u', ['id', 'fullName', 'email'])}
         FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id
        WHERE u.status = 'ACTIVE' AND p.\`key\` = 'orders.create'
        ORDER BY u.full_name ASC`,
    );

  async function getExisting(id) {
    const user = await db.one(`SELECT ${cols('user', 'u', USER_FIELDS)} FROM users u WHERE u.id = ?`, [id]);
    if (!user) throw notFound(`User ${id} not found`);
    return (await withRoles([user]))[0];
  }

  /** notifyChannel SMS needs a phone; SMS sign-in codes need a phone. Shared by admin + self edits. */
  function assertContactRules(next) {
    if (next.notifyChannel === 'SMS' && !next.phone) throw badRequest('Add a phone number to receive notifications by SMS');
    if (next.mfaMethod === 'SMS' && !next.phone) {
      throw conflict('This user signs in with SMS codes — switch their sign-in verification off or to another method before removing the phone number');
    }
  }

  async function create(dto) {
    if (await db.one('SELECT id FROM users WHERE email = ?', [dto.email])) {
      throw conflict('A user with this email already exists');
    }
    const phone = normalizePhone(dto.phone) ?? null;
    const notifyChannel = dto.notifyChannel ?? 'EMAIL';
    assertContactRules({ phone, notifyChannel, mfaMethod: 'NONE' });
    const passwordHash = await argon2.hash(dto.password);
    const id = await db.transaction(async (tx) => {
      const user = await models.insert('user', { email: dto.email, passwordHash, fullName: dto.fullName, phone, notifyChannel }, tx);
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: user.id, roleId })), tx);
      }
      return user.id;
    });
    return getExisting(id);
  }

  async function update(id, dto) {
    const current = await getExisting(id);
    const phone = normalizePhone(dto.phone);
    assertContactRules({
      phone: phone === undefined ? current.phone : phone,
      notifyChannel: dto.notifyChannel ?? current.notifyChannel,
      mfaMethod: current.mfaMethod,
    });
    const passwordHash = dto.password ? await argon2.hash(dto.password) : undefined;
    await db.transaction(async (tx) => {
      if (dto.roleIds) await db.exec('DELETE FROM user_roles WHERE user_id = ?', [id], tx);
      await models.update(
        'user',
        id,
        {
          fullName: dto.fullName ?? undefined,
          status: dto.status ?? undefined,
          phone,
          notifyChannel: dto.notifyChannel ?? undefined,
          passwordHash,
        },
        'User',
        tx,
      );
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: id, roleId })), tx);
      }
    });
    return getExisting(id);
  }

  /** Self-service profile: name, phone, how to receive notifications. */
  async function updateOwnProfile(userId, dto) {
    const current = await getExisting(userId);
    const phone = normalizePhone(dto.phone);
    if (current.mfaMethod === 'SMS' && phone !== undefined && phone !== current.phone) {
      throw conflict('You sign in with SMS codes — turn sign-in verification off (or switch method) before changing your phone number');
    }
    assertContactRules({
      phone: phone === undefined ? current.phone : phone,
      notifyChannel: dto.notifyChannel ?? current.notifyChannel,
      mfaMethod: current.mfaMethod,
    });
    await models.update('user', userId, { fullName: dto.fullName ?? undefined, phone, notifyChannel: dto.notifyChannel ?? undefined }, 'User');
    return getExisting(userId);
  }

  /** Self-service change-password: gated by proving the current one, not by a permission. */
  async function changeOwnPassword(userId, dto) {
    const user = await db.one('SELECT password_hash AS passwordHash FROM users WHERE id = ?', [userId]);
    if (!user) throw notFound(`User ${userId} not found`);
    if (!(await argon2.verify(user.passwordHash, dto.currentPassword))) throw unauthorized('Current password is incorrect');
    await models.update('user', userId, { passwordHash: await argon2.hash(dto.newPassword) }, 'User');
    return { success: true };
  }

  /** Admin: turns a user's sign-in verification off (lost phone / new device). They can re-enrol. */
  async function resetMfa(id) {
    await getExisting(id);
    await models.update('user', id, { mfaMethod: 'NONE', totpSecret: null }, 'User');
    return getExisting(id);
  }

  async function remove(id) {
    await getExisting(id);
    // Never hard-deleted: audit_logs / orders keep a valid author (rule 10).
    await models.update('user', id, { status: 'INACTIVE' }, 'User');
    return getExisting(id);
  }

  return { findAll, findConsultants, findOne: getExisting, getExisting, create, update, updateOwnProfile, changeOwnPassword, resetMfa, remove };
}

const roleIds = arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true });
// Loosely shaped here; the service normalises to +E.164 and gives a friendly error.
const phone = opt(str({ maxLength: 32 }));

function usersRoutes(app) {
  const { users, otp } = app.services;
  const manage = [app.authenticate, app.requirePermissions('users.manage')];
  const idParams = { params: uuidParams('id') };
  // Setting a user INACTIVE/SUSPENDED is a deactivation, same as DELETE.
  const deactivating = (req) => req.body.status != null && req.body.status !== 'ACTIVE';

  app.get('/me', { onRequest: [app.authenticate] }, async (request) => users.findOne(request.user.id));

  // A minimal directory for pickers (assigning a customer's consultant, sale-campaign eligibility)
  // — gated on customers.view, not users.manage, since that's the permission every caller who
  // actually needs this (Manager/Admin) already holds, and the data returned (id/name/email) is
  // non-sensitive directory info, not full user management.
  app.get('/consultants', { onRequest: [app.authenticate, app.requirePermissions('customers.view')] }, async () =>
    users.findConsultants(),
  );

  // Self-service profile: name, phone number, notification channel.
  app.patch(
    '/me',
    {
      onRequest: [app.authenticate],
      schema: { body: obj({ fullName: opt(str({ minLength: 1 })), phone, notifyChannel: opt(enumOf(NotifyChannel)) }) },
    },
    async (request) => {
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      return users.updateOwnProfile(request.user.id, request.body);
    },
  );

  app.patch(
    '/me/password',
    {
      onRequest: [app.authenticate],
      schema: {
        body: obj({ currentPassword: str(), newPassword: str({ minLength: 8 }) }, ['currentPassword', 'newPassword']),
      },
    },
    async (request) => {
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      return users.changeOwnPassword(request.user.id, request.body);
    },
  );

  app.get('/', { onRequest: manage }, async () => users.findAll());
  app.get('/:id', { onRequest: manage, schema: idParams }, async (request) => users.findOne(request.params.id));

  app.post(
    '/',
    {
      onRequest: manage,
      schema: {
        body: obj(
          {
            email: str({ format: 'email' }),
            password: str({ minLength: 8 }),
            fullName: str(),
            phone,
            notifyChannel: opt(enumOf(NotifyChannel)),
            roleIds: opt(roleIds),
          },
          ['email', 'password', 'fullName'],
        ),
      },
    },
    async (request) => users.create(request.body),
  );

  app.patch(
    '/:id',
    {
      onRequest: manage,
      preHandler: [otp.requireOtp('user.deactivate', { when: deactivating })],
      schema: {
        ...idParams,
        body: obj({
          fullName: opt(str()),
          password: opt(str({ minLength: 8 })),
          status: opt(enumOf(UserStatus)),
          phone,
          notifyChannel: opt(enumOf(NotifyChannel)),
          roleIds: opt(roleIds),
        }),
      },
    },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      return users.update(request.params.id, request.body);
    },
  );

  app.post('/:id/mfa/reset', { onRequest: manage, schema: idParams }, async (request, res) => {
    request.auditOldValue = await users.getExisting(request.params.id);
    request.auditAction = 'MFA_RESET';
    res.status(200);
    return users.resetMfa(request.params.id);
  });

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('user.deactivate')], schema: idParams },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      request.auditAction = 'DEACTIVATE';
      return users.remove(request.params.id);
    },
  );
}

module.exports = { createUsersService, usersRoutes };
