'use strict';

const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

function createWarehousesService({ prisma, cache, config }) {
  const cacheOpts = { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.STRUCTURE] };

  const findAll = (query = {}) =>
    cache.wrap(`warehouses:list:${query.includeInactive ? 'all' : 'active'}`, cacheOpts, () =>
      prisma.warehouse.findMany({
        where: { isActive: query.includeInactive ? undefined : true },
        orderBy: { name: 'asc' },
      }),
    );

  // Never cached: used by writers (and audit old-values) that must see the row as it is right now.
  async function getExisting(id) {
    const warehouse = await prisma.warehouse.findUnique({ where: { id } });
    if (!warehouse) throw notFound(`Warehouse ${id} not found`);
    return warehouse;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  const countActive = () => prisma.warehouse.count({ where: { isActive: true } });

  async function create(dto) {
    const existing = await prisma.warehouse.findUnique({ where: { code: dto.code } });
    if (existing) throw conflict('A warehouse with this code already exists');
    const created = await prisma.warehouse.create({ data: { name: dto.name, code: dto.code } });
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return created;
  }

  async function update(id, dto) {
    await getExisting(id);
    if (dto.code) {
      const existing = await prisma.warehouse.findUnique({ where: { code: dto.code } });
      if (existing && existing.id !== id) throw conflict('A warehouse with this code already exists');
    }
    const updated = await prisma.warehouse.update({
      where: { id },
      data: { name: dto.name ?? undefined, code: dto.code ?? undefined, isActive: dto.isActive ?? undefined },
    });
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return updated;
  }

  async function remove(id) {
    // Structural reference data is soft-deleted (rule 10).
    const removed = await prisma.warehouse.update({ where: { id }, data: { isActive: false } });
    await cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE);
    return removed;
  }

  return { findAll, findOne: getExisting, getExisting, countActive, create, update, remove };
}

module.exports = { createWarehousesService };
