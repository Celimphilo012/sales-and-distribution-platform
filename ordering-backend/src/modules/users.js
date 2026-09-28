'use strict';

const argon2 = require('argon2');
const { conflict, notFound, unauthorized } = require('../core/errors');
const { cols, groupBy } = require('../core/models');
const { UserStatus } = require('../core/enums');
const { obj, str, opt, arrayOf, enumOf, uuidParams } = require('../core/schema');

// The password hash never leaves this service.
const USER_FIELDS = ['id', 'email', 'fullName', 'status', 'createdAt', 'updatedAt'];

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

  async function getExisting(id) {
    const user = await db.one(`SELECT ${cols('user', 'u', USER_FIELDS)} FROM users u WHERE u.id = ?`, [id]);
    if (!user) throw notFound(`User ${id} not found`);
    return (await withRoles([user]))[0];
  }

  async function create(dto) {
    if (await db.one('SELECT id FROM users WHERE email = ?', [dto.email])) {
      throw conflict('A user with this email already exists');
    }
    const passwordHash = await argon2.hash(dto.password);
    const id = await db.transaction(async (tx) => {
      const user = await models.insert('user', { email: dto.email, passwordHash, fullName: dto.fullName }, tx);
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: user.id, roleId })), tx);
      }
      return user.id;
    });
    return getExisting(id);
  }

  async function update(id, dto) {
    await getExisting(id);
    const passwordHash = dto.password ? await argon2.hash(dto.password) : undefined;
    await db.transaction(async (tx) => {
      if (dto.roleIds) await db.exec('DELETE FROM user_roles WHERE user_id = ?', [id], tx);
      await models.update(
        'user',
        id,
        { fullName: dto.fullName ?? undefined, status: dto.status ?? undefined, passwordHash },
        'User',
        tx,
      );
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: id, roleId })), tx);
      }
    });
    return getExisting(id);
  }

  /** Self-service change-password: gated by proving the current one, not by a permission. */
  async function changeOwnPassword(userId, dto) {
    const user = await db.one('SELECT password_hash AS passwordHash FROM users WHERE id = ?', [userId]);
    if (!user) throw notFound(`User ${userId} not found`);
    if (!(await argon2.verify(user.passwordHash, dto.currentPassword))) throw unauthorized('Current password is incorrect');
    await models.update('user', userId, { passwordHash: await argon2.hash(dto.newPassword) }, 'User');
    return { success: true };
  }

  async function remove(id) {
    await getExisting(id);
    // Never hard-deleted: audit_logs / orders keep a valid author (rule 10).
    await models.update('user', id, { status: 'INACTIVE' }, 'User');
    return getExisting(id);
  }

  return { findAll, findOne: getExisting, getExisting, create, update, changeOwnPassword, remove };
}

const roleIds = arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true });

function usersRoutes(app) {
  const { users } = app.services;
  const manage = [app.authenticate, app.requirePermissions('users.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/me', { onRequest: [app.authenticate] }, async (request) => users.findOne(request.user.id));

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
          { email: str({ format: 'email' }), password: str({ minLength: 8 }), fullName: str(), roleIds: opt(roleIds) },
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
      schema: {
        ...idParams,
        body: obj({
          fullName: opt(str()),
          password: opt(str({ minLength: 8 })),
          status: opt(enumOf(UserStatus)),
          roleIds: opt(roleIds),
        }),
      },
    },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      return users.update(request.params.id, request.body);
    },
  );

  app.delete('/:id', { onRequest: manage, schema: idParams }, async (request) => {
    request.auditOldValue = await users.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return users.remove(request.params.id);
  });
}

module.exports = { createUsersService, usersRoutes };
