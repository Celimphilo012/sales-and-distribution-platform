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
    const rows = await cache.wrap(key, cacheOpts, () => {
      const where = new Where().in('w.id', scope ?? undefined);
      if (!query.includeInactive) where.raw('w.is_active = true');
      return db.query(`SELECT ${cols('warehouse', 'w')} FROM warehouses w ${where.sql} ORDER BY w.name ASC`, where.params);
    });
    return attachSummary(rows);
  }

  /**
   * Each warehouse's structure + stock totals as `summary: {locations, slots, units, capacity,
   * workstreams}` — active locations only; a slot is a leaf (no active children); capacity sums the
   * slots that have one. DB-level aggregates, read fresh (stock moves constantly).
   */
  async function attachSummary(rows) {
    if (rows.length === 0) return rows;
    const ids = rows.map((w) => w.id);
    const where = new Where().raw('l.is_active = true').in('l.warehouse_id', ids);
    const stockWhere = new Where().in('l.warehouse_id', ids);
    const streamWhere = new Where().raw('is_active = true').in('warehouse_id', ids);
    const [structure, stock, streams] = await Promise.all([
      db.query(
        `SELECT l.warehouse_id AS warehouseId, COUNT(*) AS locations,
                SUM(CASE WHEN c.id IS NULL THEN 1 ELSE 0 END) AS slots,
                SUM(CASE WHEN c.id IS NULL THEN l.capacity ELSE 0 END) AS capacity
           FROM locations l
           LEFT JOIN (SELECT DISTINCT parent_id AS id FROM locations WHERE is_active = true AND parent_id IS NOT NULL) c ON c.id = l.id
           ${where.sql} GROUP BY l.warehouse_id`,
        where.params,
      ),
      db.query(
        `SELECT l.warehouse_id AS warehouseId, SUM(b.on_hand) AS units
           FROM inventory_balances b JOIN locations l ON l.id = b.location_id
           ${stockWhere.sql} GROUP BY l.warehouse_id`,
        stockWhere.params,
      ),
      db.query(
        `SELECT warehouse_id AS warehouseId, COUNT(*) AS n FROM workstreams
           ${streamWhere.sql} GROUP BY warehouse_id`,
        streamWhere.params,
      ),
    ]);
    const by = (list, id) => list.find((r) => r.warehouseId === id);
    return rows.map((w) => {
      const s = by(structure, w.id);
      return {
        ...w,
        summary: {
          locations: Number(s?.locations ?? 0),
          slots: Number(s?.slots ?? 0),
          capacity: Number(s?.capacity ?? 0),
          units: Number(by(stock, w.id)?.units ?? 0),
          workstreams: Number(by(streams, w.id)?.n ?? 0),
        },
      };
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
