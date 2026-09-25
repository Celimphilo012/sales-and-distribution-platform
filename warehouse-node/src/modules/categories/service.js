'use strict';

const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const CATEGORY_INCLUDE = { workstream: { select: { id: true, name: true, code: true } } };

function createCategoriesService({ prisma, cache, config, workstreams, workstreamManagers }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

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

  /** [viewerId], when given, narrows the result to categories in a workstream that viewer is assigned to. */
  async function findAll(options = {}, viewerId) {
    const workstreamId = await effectiveWorkstreamIdFilter(options.workstreamId, viewerId);
    const wsKey = workstreamId && typeof workstreamId === 'object' ? `in:${workstreamId.in.join(',')}` : (workstreamId ?? '-');
    const key = `categories:list:${options.includeInactive ? 'all' : 'active'}:${options.parentId ?? '-'}:${wsKey}`;

    return cache.wrap(key, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] }, () =>
      prisma.category.findMany({
        where: {
          isActive: options.includeInactive ? undefined : true,
          parentId: options.parentId,
          workstreamId,
        },
        include: CATEGORY_INCLUDE,
        orderBy: { name: 'asc' },
      }),
    );
  }

  // Never cached: writers (and audit old-values) must see the row as it is right now.
  async function getExisting(id) {
    const category = await prisma.category.findUnique({ where: { id } });
    if (!category) throw notFound(`Category ${id} not found`);
    return category;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  const countActive = () => prisma.category.count({ where: { isActive: true } });

  /** [viewerId], when given, 403s if that viewer is scoped and this category's workstream isn't one of theirs. */
  async function findOne(id, viewerId) {
    const category = await prisma.category.findUnique({ where: { id }, include: CATEGORY_INCLUDE });
    if (!category) throw notFound(`Category ${id} not found`);
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
      const parent = await prisma.category.findUnique({ where: { id: currentId }, select: { parentId: true } });
      currentId = parent?.parentId ?? null;
    }
  }

  async function create(dto, actingUserId) {
    await workstreams.getExisting(dto.workstreamId);
    await workstreamManagers.assertScopedAccess(actingUserId, dto.workstreamId);

    if (dto.parentId) {
      const parent = await getExisting(dto.parentId);
      if (parent.workstreamId !== dto.workstreamId) {
        throw badRequest('A sub-category must belong to the same workstream as its parent category');
      }
    }

    const created = await prisma.category.create({
      data: { name: dto.name, parentId: dto.parentId ?? null, workstreamId: dto.workstreamId },
      include: CATEGORY_INCLUDE,
    });
    await invalidate();
    return created;
  }

  async function update(id, dto, actingUserId) {
    const existing = await getExisting(id);

    // Scoped to the category's CURRENT workstream always — moving it to a new one additionally
    // requires scope over the DESTINATION, so a manager can't move a category into a workstream
    // they don't hold.
    await workstreamManagers.assertScopedAccess(actingUserId, existing.workstreamId);

    if (dto.workstreamId !== undefined && dto.workstreamId !== existing.workstreamId) {
      await workstreams.getExisting(dto.workstreamId);
      await workstreamManagers.assertScopedAccess(actingUserId, dto.workstreamId);

      const childCount = await prisma.category.count({ where: { parentId: id } });
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

    const updated = await prisma.category.update({
      where: { id },
      data: {
        name: dto.name ?? undefined,
        isActive: dto.isActive ?? undefined,
        workstreamId: dto.workstreamId ?? undefined,
        ...(dto.parentId !== undefined ? { parentId: dto.parentId } : {}),
      },
      include: CATEGORY_INCLUDE,
    });
    await invalidate();
    return updated;
  }

  async function remove(id, actingUserId) {
    const existing = await getExisting(id);
    await workstreamManagers.assertScopedAccess(actingUserId, existing.workstreamId);

    // Reference data is soft-deleted (rule 10) — products keep a valid historical category reference.
    const removed = await prisma.category.update({
      where: { id },
      data: { isActive: false },
      include: CATEGORY_INCLUDE,
    });
    await invalidate();
    return removed;
  }

  return { findAll, findOne, getExisting, countActive, create, update, remove };
}

module.exports = { createCategoriesService };
