'use strict';

const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, groupBy } = require('../../core/models');

function createRolesService({ db, models, cache }) {
  /** Attaches permissions: [{ id, key, description, module }] to each role, one query for the list. */
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
    return roles.map((r) => ({
      ...r,
      permissions: (byRole.get(r.id) ?? []).map(({ roleId, ...permission }) => permission),
    }));
  }

  async function findAll() {
    const roles = await db.query(`SELECT ${cols('role', 'r')} FROM roles r ORDER BY r.name ASC`);
    return withPermissions(roles);
  }

  async function getExisting(id, executor) {
    const role = await models.findById('role', id, executor);
    if (!role) throw notFound(`Role ${id} not found`);
    const [withPerms] = await withPermissions([role], executor);
    return withPerms;
  }

  async function create(dto) {
    const existing = await db.one('SELECT id FROM roles WHERE name = ?', [dto.name]);
    if (existing) throw conflict('A role with this name already exists');

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

    // Its role_permissions rows go with it (ON DELETE CASCADE).
    await db.exec('DELETE FROM roles WHERE id = ?', [id]);
    return { id, deleted: true };
  }

  async function assignPermissions(id, dto) {
    await getExisting(id);

    const role = await db.transaction(async (tx) => {
      await db.exec('DELETE FROM role_permissions WHERE role_id = ?', [id], tx);
      await models.insertMany(
        'rolePermission',
        dto.permissionIds.map((permissionId) => ({ roleId: id, permissionId })),
        tx,
      );
      return getExisting(id, tx);
    });

    // Effective permissions changed for every user holding this role.
    await cache.invalidate(TAGS.PERMISSIONS);
    return role;
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove, assignPermissions };
}

module.exports = { createRolesService };
