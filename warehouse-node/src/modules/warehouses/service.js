'use strict';

const { conflict } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, Where } = require('../../core/models');

/**
 * `viewerId` / `actingUserId` is the signed-in user; every read is narrowed to the warehouses they
 * may access and every write checks it (modules/access — deny by default). Internal callers that
 * pass no user id are unscoped.
 */
function createWarehousesService({ db, models, cache, config, access }) {
  const cacheOpts = { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.STRUCTURE] };

  async function findAll(query = {}, viewerId) {
    const scope = await access.warehouseScope(viewerId);
    const key = `warehouses:list:${query.includeInactive ? 'all' : 'active'}:${access.scopeKey(scope)}`;
    return cache.wrap(key, cacheOpts, () => {
      const where = new Where().in('w.id', scope ?? undefined);
      if (!query.includeInactive) where.raw('w.is_active = true');
      return db.query(`SELECT ${cols('warehouse', 'w')} FROM warehouses w ${where.sql} ORDER BY w.name ASC`, where.params);
    });
  }

  // Never cached: used by writers (and audit old-values) that must see the row as it is right now.
  const getExisting = (id) => models.getById('warehouse', id, 'Warehouse');

  async function findOne(id, viewerId) {
    const warehouse = await getExisting(id);
    await access.assertWarehouse(viewerId, id);
    return warehouse;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary, within the viewer's warehouses. */
  async function countActive(scope = null) {
    const where = new Where().raw('is_active = true').in('id', scope ?? undefined);
    return Number((await db.one(`SELECT COUNT(*) AS n FROM warehouses ${where.sql}`, where.params)).n);
  }

  const findByCode = (code) => db.one('SELECT id FROM warehouses WHERE code = ?', [code]);

  async function create(dto, actingUserId) {
    if (await findByCode(dto.code)) throw conflict('A warehouse with this code already exists');
    const created = await models.insert('warehouse', { name: dto.name, code: dto.code });
    // A creator without all-warehouse access would otherwise be locked out of what they just made.
    if (actingUserId && !(await access.canAccessWarehouse(actingUserId, created.id))) {
      await models.insert('userWarehouse', { userId: actingUserId, warehouseId: created.id });
      await cache.invalidate(TAGS.SCOPES);
    }
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return created;
  }

  async function update(id, dto, actingUserId) {
    await getExisting(id);
    await access.assertWarehouse(actingUserId, id);
    if (dto.code) {
      const existing = await findByCode(dto.code);
      if (existing && existing.id !== id) throw conflict('A warehouse with this code already exists');
    }
    const updated = await models.update(
      'warehouse',
      id,
      { name: dto.name ?? undefined, code: dto.code ?? undefined, isActive: dto.isActive ?? undefined },
      'Warehouse',
    );
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return updated;
  }

  async function remove(id, actingUserId) {
    await getExisting(id);
    await access.assertWarehouse(actingUserId, id);
    // Structural reference data is soft-deleted (rule 10).
    const removed = await models.update('warehouse', id, { isActive: false }, 'Warehouse');
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return removed;
  }

  return { findAll, findOne, getExisting, countActive, create, update, remove };
}

module.exports = { createWarehousesService };
