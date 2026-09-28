'use strict';

const { badRequest, forbidden, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const ALL_WAREHOUSES_PERMISSION = 'warehouse.access.all';

/**
 * Warehouse-level access control — deny by default. A user may see and act on a warehouse (its
 * locations, stock, workstreams, categories and products) only if they are assigned to it in
 * `user_warehouses`, or hold the `warehouse.access.all` permission (granted to ADMIN). Workstream
 * manager assignments (workstream_managers) then narrow catalogue management further, and may only
 * be made inside a warehouse the user can access.
 *
 * Every service that reads or writes warehouse-owned data calls warehouseScope()/assertWarehouse()
 * with the ACTING user's id. Internal callers that pass no user id (seeds, the external API-key
 * API, which is system-to-system) are unscoped.
 */
function createAccessService({ db, models, cache, config, auth }) {
  const cacheOpts = { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.SCOPES] };

  /** null = every warehouse; otherwise the (possibly empty) list of warehouse ids the user may access. */
  async function warehouseScope(userId) {
    if (!userId) return null;
    const permissions = await auth.resolveEffectivePermissionKeys(userId);
    if (permissions.includes(ALL_WAREHOUSES_PERMISSION)) return null;
    return cache.wrap(`warehouse-scope:${userId}`, cacheOpts, async () => {
      const rows = await db.query('SELECT warehouse_id AS warehouseId FROM user_warehouses WHERE user_id = ?', [userId]);
      return rows.map((r) => r.warehouseId);
    });
  }

  /** Stable cache-key fragment for a scope. */
  const scopeKey = (ids) => (ids === null ? 'all' : [...ids].sort().join(',') || 'none');

  async function canAccessWarehouse(userId, warehouseId) {
    const ids = await warehouseScope(userId);
    return ids === null || ids.includes(warehouseId);
  }

  async function assertWarehouse(userId, warehouseId) {
    if (!(await canAccessWarehouse(userId, warehouseId))) {
      throw forbidden('You do not have access to this warehouse');
    }
  }

  /** The warehouses a user is assigned to (not what access.all grants — that is a permission). */
  function listForUser(userId) {
    return db.query(
      `SELECT w.id, w.name, w.code, w.is_active AS isActive
         FROM user_warehouses uw JOIN warehouses w ON w.id = uw.warehouse_id
        WHERE uw.user_id = ?
        ORDER BY w.name ASC`,
      [userId],
    );
  }

  /** Assignments for many users at once: Map<userId, [{ id, name, code }]>. */
  async function listForUsers(userIds) {
    const map = new Map(userIds.map((id) => [id, []]));
    if (userIds.length === 0) return map;
    const rows = await db.query(
      `SELECT uw.user_id AS userId, w.id, w.name, w.code
         FROM user_warehouses uw JOIN warehouses w ON w.id = uw.warehouse_id
        WHERE uw.user_id IN (?)
        ORDER BY w.name ASC`,
      [userIds],
    );
    for (const { userId, ...warehouse } of rows) map.get(userId)?.push(warehouse);
    return map;
  }

  /**
   * Replaces a user's warehouse assignments. Losing a warehouse also removes the user's workstream
   * manager assignments inside it (the hierarchy is warehouse, then workstream).
   */
  async function setForUser(userId, warehouseIds) {
    const user = await db.one('SELECT id FROM users WHERE id = ?', [userId]);
    if (!user) throw notFound(`User ${userId} not found`);
    const unique = [...new Set(warehouseIds)];
    if (unique.length) {
      const found = await db.query('SELECT id FROM warehouses WHERE id IN (?)', [unique]);
      if (found.length !== unique.length) {
        const known = new Set(found.map((w) => w.id));
        throw badRequest(`Warehouse ${unique.find((id) => !known.has(id))} does not exist`);
      }
    }

    await db.transaction(async (tx) => {
      if (unique.length) {
        await db.exec('DELETE FROM user_warehouses WHERE user_id = ? AND warehouse_id NOT IN (?)', [userId, unique], tx);
        await db.exec(
          `DELETE wm FROM workstream_managers wm JOIN workstreams ws ON ws.id = wm.workstream_id
            WHERE wm.user_id = ? AND ws.warehouse_id NOT IN (?)`,
          [userId, unique],
          tx,
        );
      } else {
        await db.exec('DELETE FROM user_warehouses WHERE user_id = ?', [userId], tx);
        await db.exec('DELETE FROM workstream_managers WHERE user_id = ?', [userId], tx);
      }
      const existing = new Set(
        (await db.query('SELECT warehouse_id AS warehouseId FROM user_warehouses WHERE user_id = ?', [userId], tx)).map(
          (r) => r.warehouseId,
        ),
      );
      const toAdd = unique.filter((id) => !existing.has(id));
      await models.insertMany('userWarehouse', toAdd.map((warehouseId) => ({ userId, warehouseId })), tx);
    });

    await cache.invalidate(TAGS.SCOPES);
    return listForUser(userId);
  }

  return { warehouseScope, scopeKey, canAccessWarehouse, assertWarehouse, listForUser, listForUsers, setForUser };
}

module.exports = { createAccessService, ALL_WAREHOUSES_PERMISSION };
