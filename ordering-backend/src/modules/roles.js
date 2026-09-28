'use strict';

const { conflict, notFound } = require('../core/errors');
const { cols, groupBy } = require('../core/models');
const { obj, str, opt, arrayOf, uuidParams } = require('../core/schema');

function createRolesService({ db, models }) {
  async function withPermissions(roles, executor) {
    if (roles.length === 0) return roles;
    const rows = await db.query(
      `SELECT rp.role_id AS roleId, ${cols('permission', 'p')}
         FROM role_permissions rp JOIN permissions p ON p.id = rp.permission_id
        WHERE rp.role_id IN (?)`,
      [roles.map((r) => r.id)],
      executor,
    );
    const byRole = groupBy(rows, 'roleId');
    return roles.map((r) => ({ ...r, permissions: (byRole.get(r.id) ?? []).map(({ roleId, ...p }) => p) }));
  }

  const findAll = async () => withPermissions(await db.query(`SELECT ${cols('role', 'r')} FROM roles r ORDER BY r.name ASC`));

  async function getExisting(id, executor) {
    const role = await models.findById('role', id, executor);
    if (!role) throw notFound(`Role ${id} not found`);
    return (await withPermissions([role], executor))[0];
  }

  async function create(dto) {
    if (await db.one('SELECT id FROM roles WHERE name = ?', [dto.name])) throw conflict('A role with this name already exists');
    const role = await models.insert('role', { name: dto.name, description: dto.description });
    return getExisting(role.id);
  }

  async function update(id, dto) {
    const existing = await models.findById('role', id);
    if (!existing) throw notFound(`Role ${id} not found`);
    if (existing.isSystem && dto.name) throw conflict('Cannot rename a system role');
    await models.update('role', id, { name: dto.name ?? undefined, description: dto.description }, 'Role');
    return getExisting(id);
  }

  async function remove(id) {
    const existing = await models.findById('role', id);
    if (!existing) throw notFound(`Role ${id} not found`);
    if (existing.isSystem) throw conflict('Cannot delete a system role');
    const { assigned } = await db.one('SELECT COUNT(*) AS assigned FROM user_roles WHERE role_id = ?', [id]);
    if (assigned > 0) throw conflict('Cannot delete a role that is still assigned to users');
    await db.exec('DELETE FROM roles WHERE id = ?', [id]); // role_permissions cascade
    return { id, deleted: true };
  }

  async function assignPermissions(id, dto) {
    await getExisting(id);
    return db.transaction(async (tx) => {
      await db.exec('DELETE FROM role_permissions WHERE role_id = ?', [id], tx);
      await models.insertMany('rolePermission', dto.permissionIds.map((permissionId) => ({ roleId: id, permissionId })), tx);
      return getExisting(id, tx);
    });
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove, assignPermissions };
}

function rolesRoutes(app) {
  const { roles } = app.services;
  const guard = [app.authenticate, app.requirePermissions('roles.manage')];
  const idParams = { params: uuidParams('id') };

  app.get('/', { onRequest: guard }, async () => roles.findAll());
  app.get('/:id', { onRequest: guard, schema: idParams }, async (request) => roles.findOne(request.params.id));
  app.post(
    '/',
    { onRequest: guard, schema: { body: obj({ name: str({ minLength: 2 }), description: opt(str()) }, ['name']) } },
    async (request) => roles.create(request.body),
  );
  app.patch(
    '/:id',
    { onRequest: guard, schema: { ...idParams, body: obj({ name: opt(str({ minLength: 2 })), description: opt(str()) }) } },
    async (request) => {
      request.auditOldValue = await roles.getExisting(request.params.id);
      return roles.update(request.params.id, request.body);
    },
  );
  app.put(
    '/:id/permissions',
    {
      onRequest: guard,
      schema: {
        ...idParams,
        body: obj({ permissionIds: arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true }) }, ['permissionIds']),
      },
    },
    async (request) => {
      request.auditOldValue = await roles.getExisting(request.params.id);
      request.auditAction = 'ASSIGN_PERMISSIONS';
      return roles.assignPermissions(request.params.id, request.body);
    },
  );
  app.delete('/:id', { onRequest: guard, schema: idParams }, async (request) => {
    request.auditOldValue = await roles.getExisting(request.params.id);
    return roles.remove(request.params.id);
  });
}

function permissionsRoutes(app) {
  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('roles.manage')] }, async () =>
    app.db.query(`SELECT ${cols('permission', 'p')} FROM permissions p ORDER BY p.module ASC, p.key ASC`),
  );
}

module.exports = { createRolesService, rolesRoutes, permissionsRoutes };
