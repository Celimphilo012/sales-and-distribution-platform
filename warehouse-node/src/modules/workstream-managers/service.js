'use strict';

const { badRequest, conflict, forbidden, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { isUniqueViolation } = require('../../core/db');
const { cols, nest } = require('../../core/models');

const MANAGER_SELECT = `
  SELECT ${cols('workstreamManager', 'm')},
         ${cols('user', 'u', ['id', 'email', 'fullName', 'status'], 'user.')}
    FROM workstream_managers m
    JOIN users u ON u.id = m.user_id`;

/**
 * Owns the workstream_managers assignment table and the scoping check it drives. A user with ANY
 * assignment row is restricted, for catalogue mutations (categories + products), to only their
 * assigned workstream(s); a user with none is unscoped. Data-driven, never keyed off a role name
 * (CLAUDE.md rule 1).
 *
 * Assignments sit INSIDE warehouse access (modules/access): a user can only be made manager of a
 * workstream whose warehouse they are assigned to, and losing that warehouse removes the assignment.
 *
 * Depends only on the db, the cache and the access service so Workstreams/Categories/Products can
 * all use it for scoping without a circular dependency.
 */
function createWorkstreamManagersService({ db, models, cache, config, access }) {
  async function loadWorkstream(workstreamId, actingUserId) {
    const workstream = await db.one('SELECT id, warehouse_id AS warehouseId FROM workstreams WHERE id = ?', [workstreamId]);
    if (!workstream) throw notFound(`Workstream ${workstreamId} not found`);
    await access.assertWarehouse(actingUserId, workstream.warehouseId);
    return workstream;
  }

  async function listForWorkstream(workstreamId, viewerId) {
    await loadWorkstream(workstreamId, viewerId);
    return (await db.query(`${MANAGER_SELECT} WHERE m.workstream_id = ? ORDER BY m.created_at ASC`, [workstreamId])).map(nest);
  }

  const listForUser = async (userId) =>
    (
      await db.query(
        `SELECT ${cols('workstreamManager', 'm', ['id', 'workstreamId', 'createdAt'])},
                ${cols('workstream', 'w', ['id', 'name', 'code'], 'workstream.')}
           FROM workstream_managers m
           JOIN workstreams w ON w.id = m.workstream_id
          WHERE m.user_id = ?
          ORDER BY m.created_at ASC`,
        [userId],
      )
    ).map(nest);

  /**
   * The workstream IDs a user is scoped to. Empty means "unscoped". Read on nearly every catalogue
   * request (list scoping + every mutation's scope check), so it is cached and invalidated on
   * assign/unassign.
   */
  const getAssignedWorkstreamIds = (userId) =>
    cache.wrap(`scopes:${userId}`, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.SCOPES] }, async () => {
      const rows = await db.query('SELECT workstream_id AS workstreamId FROM workstream_managers WHERE user_id = ?', [userId]);
      return rows.map((r) => r.workstreamId);
    });

  /**
   * The enforcement point — called before every catalogue mutation with the workstream the target
   * row belongs to. A no-op for an unscoped user; throws for a scoped user acting outside their
   * assigned workstream(s).
   */
  async function assertScopedAccess(userId, workstreamId) {
    const assignedIds = await getAssignedWorkstreamIds(userId);
    if (assignedIds.length === 0) return;
    if (!assignedIds.includes(workstreamId)) throw forbidden('You are not assigned to manage this workstream');
  }

  async function assign(workstreamId, userId, actingUserId) {
    const workstream = await loadWorkstream(workstreamId, actingUserId);
    const user = await db.one('SELECT id FROM users WHERE id = ?', [userId]);
    if (!user) throw notFound(`User ${userId} not found`);
    if (!(await access.canAccessWarehouse(userId, workstream.warehouseId))) {
      throw badRequest("Give this user access to the workstream's warehouse first (Users → Warehouses)");
    }

    let row;
    try {
      row = await models.insert('workstreamManager', { userId, workstreamId });
    } catch (error) {
      if (isUniqueViolation(error)) throw conflict('This user is already assigned to this workstream');
      throw error;
    }
    await cache.invalidate(TAGS.SCOPES);
    return nest(await db.one(`${MANAGER_SELECT} WHERE m.id = ?`, [row.id]));
  }

  async function unassign(workstreamId, userId, actingUserId) {
    await loadWorkstream(workstreamId, actingUserId);
    const existing = await db.one('SELECT id FROM workstream_managers WHERE user_id = ? AND workstream_id = ?', [
      userId,
      workstreamId,
    ]);
    if (!existing) throw notFound('This user is not assigned to this workstream');
    await db.exec('DELETE FROM workstream_managers WHERE id = ?', [existing.id]);
    await cache.invalidate(TAGS.SCOPES);
    return { workstreamId, userId, removed: true };
  }

  return { listForWorkstream, listForUser, getAssignedWorkstreamIds, assertScopedAccess, assign, unassign };
}

module.exports = { createWorkstreamManagersService };
