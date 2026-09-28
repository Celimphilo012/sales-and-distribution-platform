'use strict';

const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, nest, Where } = require('../../core/models');

// Every category read carries its workstream's { id, name, code }.
const CATEGORY_SELECT = `
  SELECT ${cols('category', 'c')},
         ${cols('workstream', 'w', ['id', 'name', 'code'], 'workstream.')}
    FROM categories c
    JOIN workstreams w ON w.id = c.workstream_id`;

function createCategoriesService({ db, models, cache, config, access, workstreams, workstreamManagers }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  async function findWithWorkstream(id) {
    const row = await db.one(`${CATEGORY_SELECT} WHERE c.id = ?`, [id]);
    return row ? nest(row) : null;
  }

  /**
   * Intersects an explicit `workstreamId` query filter (if any) with a scoped viewer's assigned
   * workstream(s) (if any): the single value if both agree, an impossible `{in: []}` if they
   * conflict (an explicit filter for a workstream the viewer isn't assigned to correctly yields
   * zero rows, not an error, since this is a list endpoint), or whichever one applies alone.
   */
  async function effectiveWorkstreamIdFilter(explicit, viewerId) {
    if (!viewerId) return explicit;
    const assignedIds = await workstreamManagers.getAssignedWorkstreamIds(viewerId);
    if (assignedIds.length === 0) return explicit;
    if (!explicit) return { in: assignedIds };
    return assignedIds.includes(explicit) ? explicit : { in: [] };
  }

  /**
   * [viewerId], when given, narrows the result to the viewer's warehouses, then to categories in a
   * workstream the viewer is assigned to manage (if they have any such assignment).
   */
  async function findAll(options = {}, viewerId) {
    const [workstreamId, warehouseIds] = await Promise.all([
      effectiveWorkstreamIdFilter(options.workstreamId, viewerId),
      access.warehouseScope(viewerId),
    ]);
    const wsKey = workstreamId && typeof workstreamId === 'object' ? `in:${workstreamId.in.join(',')}` : (workstreamId ?? '-');
    const key = `categories:list:${options.includeInactive ? 'all' : 'active'}:${options.parentId ?? '-'}:${wsKey}:${access.scopeKey(warehouseIds)}`;

    return cache.wrap(key, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] }, async () => {
      const where = new Where().eq('c.parent_id', options.parentId).in('w.warehouse_id', warehouseIds ?? undefined);
      if (!options.includeInactive) where.raw('c.is_active = true');
      if (workstreamId && typeof workstreamId === 'object') where.in('c.workstream_id', workstreamId.in);
      else where.eq('c.workstream_id', workstreamId);
      const rows = await db.query(`${CATEGORY_SELECT} ${where.sql} ORDER BY c.name ASC`, where.params);
      return rows.map(nest);
    });
  }

  // Never cached: writers (and audit old-values) must see the row as it is right now.
  const getExisting = (id) => models.getById('category', id, 'Category');

  /** DB-level COUNT for the reports dashboard's catalogue summary, within the given warehouses (null = all). */
  async function countActive(warehouseIds = null) {
    const where = new Where().raw('c.is_active = true').in('w.warehouse_id', warehouseIds ?? undefined);
    const row = await db.one(
      `SELECT COUNT(*) AS n FROM categories c JOIN workstreams w ON w.id = c.workstream_id ${where.sql}`,
      where.params,
    );
    return Number(row.n);
  }

  /** [viewerId], when given, 403s if that viewer is scoped and this category's workstream isn't one of theirs. */
  async function findOne(id, viewerId) {
    const category = await findWithWorkstream(id);
    if (!category) throw notFound(`Category ${id} not found`);
    await workstreams.getAccessible(category.workstreamId, viewerId);
    if (viewerId) await workstreamManagers.assertScopedAccess(viewerId, category.workstreamId);
    return category;
  }

  async function assertNoCycle(categoryId, proposedParentId) {
    let currentId = proposedParentId;
    const visited = new Set();
    while (currentId) {
      if (currentId === categoryId) {
        throw conflict('Cannot assign this parent: it would create a cycle in the category tree');
      }
      if (visited.has(currentId)) break;
      visited.add(currentId);
      const parent = await db.one('SELECT parent_id AS parentId FROM categories WHERE id = ?', [currentId]);
      currentId = parent?.parentId ?? null;
    }
  }

  async function create(dto, actingUserId) {
    await workstreams.getAccessible(dto.workstreamId, actingUserId);
    await workstreamManagers.assertScopedAccess(actingUserId, dto.workstreamId);

    if (dto.parentId) {
      const parent = await getExisting(dto.parentId);
      if (parent.workstreamId !== dto.workstreamId) {
        throw badRequest('A sub-category must belong to the same workstream as its parent category');
      }
    }

    const created = await models.insert('category', {
      name: dto.name,
      parentId: dto.parentId ?? null,
      workstreamId: dto.workstreamId,
    });
    await invalidate();
    return findWithWorkstream(created.id);
  }

  async function update(id, dto, actingUserId) {
    const existing = await getExisting(id);
    await workstreams.getAccessible(existing.workstreamId, actingUserId);

    // Scoped to the category's CURRENT workstream always — moving it to a new one additionally
    // requires scope over the DESTINATION, so a manager can't move a category into a workstream
    // they don't hold.
    await workstreamManagers.assertScopedAccess(actingUserId, existing.workstreamId);

    if (dto.workstreamId !== undefined && dto.workstreamId !== existing.workstreamId) {
      await workstreams.getAccessible(dto.workstreamId, actingUserId);
      await workstreamManagers.assertScopedAccess(actingUserId, dto.workstreamId);

      const { childCount } = await db.one('SELECT COUNT(*) AS childCount FROM categories WHERE parent_id = ?', [id]);
      if (childCount > 0) {
        throw badRequest(
          'Cannot change the workstream of a category that has sub-categories — move or update the sub-categories first',
        );
      }
    }

    if (dto.parentId !== undefined && dto.parentId !== null) {
      if (dto.parentId === id) throw badRequest('A category cannot be its own parent');
      const parent = await getExisting(dto.parentId);
      await assertNoCycle(id, dto.parentId);

      const effectiveWorkstreamId = dto.workstreamId ?? existing.workstreamId;
      if (parent.workstreamId !== effectiveWorkstreamId) {
        throw badRequest('A sub-category must belong to the same workstream as its parent category');
      }
    }

    await models.update(
      'category',
      id,
      {
        name: dto.name ?? undefined,
        isActive: dto.isActive ?? undefined,
        workstreamId: dto.workstreamId ?? undefined,
        // null is meaningful here: it moves the category to the root.
        parentId: dto.parentId,
      },
      'Category',
    );
    await invalidate();
    return findWithWorkstream(id);
  }

  async function remove(id, actingUserId) {
    const existing = await getExisting(id);
    await workstreams.getAccessible(existing.workstreamId, actingUserId);
    await workstreamManagers.assertScopedAccess(actingUserId, existing.workstreamId);

    // Reference data is soft-deleted (rule 10) — products keep a valid historical category reference.
    await models.update('category', id, { isActive: false }, 'Category');
    await invalidate();
    return findWithWorkstream(id);
  }

  return { findAll, findOne, getExisting, countActive, create, update, remove };
}

module.exports = { createCategoriesService };
