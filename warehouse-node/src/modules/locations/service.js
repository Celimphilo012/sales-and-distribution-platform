'use strict';

const { Prisma } = require('@prisma/client');
const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

/** $queryRaw returns raw driver values (snake_case, TINYINT for booleans) — map to the Prisma model shape. */
function mapRow(row) {
  return {
    id: row.id,
    warehouseId: row.warehouse_id,
    parentId: row.parent_id,
    name: row.name,
    code: row.code,
    locationType: row.location_type,
    description: row.description,
    isActive: Boolean(row.is_active),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    depth: Number(row.depth),
  };
}

function createLocationsService({ prisma, cache, config, warehouses }) {
  const cacheOpts = { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.STRUCTURE] };
  const structureChanged = () => cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE, TAGS.STOCK);

  function translateUniqueViolation(error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return conflict('A location with this code already exists in this warehouse');
    }
    return error;
  }

  const findAll = (query = {}) =>
    cache.wrap(
      `locations:list:${query.warehouseId ?? '-'}:${query.rootOnly ? 'root' : (query.parentId ?? '-')}:${query.includeInactive ? 'all' : 'active'}`,
      cacheOpts,
      () =>
        prisma.location.findMany({
          where: {
            warehouseId: query.warehouseId,
            parentId: query.rootOnly ? null : query.parentId,
            isActive: query.includeInactive ? undefined : true,
          },
          orderBy: { name: 'asc' },
        }),
    );

  // Never cached: writers and the leaf check depend on the row as it is right now.
  async function getExisting(id) {
    const location = await prisma.location.findUnique({ where: { id } });
    if (!location) throw notFound(`Location ${id} not found`);
    return location;
  }

  /**
   * Stock can only be held at leaf locations: receiving/transfer/adjustment/count locations must
   * have zero children, active or not. Deliberately NOT cached — a stale "leaf" answer would let
   * stock be written to a location that has since gained children.
   */
  async function assertLeaf(locationId) {
    const location = await getExisting(locationId);
    const childCount = await prisma.location.count({ where: { parentId: locationId } });
    if (childCount > 0) {
      throw badRequest(
        `Location "${location.name}" (${locationId}) is not a leaf location — it has ${childCount} child location(s). Stock can only be held at leaf locations.`,
      );
    }
    return location;
  }

  // The existence check lives inside the loader: locations are only ever soft-deleted, so once a
  // result is cached the parent cannot vanish, and an unknown id throws (and is never cached).
  const children = (parentId, includeInactive = false) =>
    cache.wrap(`locations:children:${parentId}:${includeInactive}`, cacheOpts, async () => {
      await getExisting(parentId);
      return prisma.location.findMany({
        where: { parentId, isActive: includeInactive ? undefined : true },
        orderBy: { name: 'asc' },
      });
    });

  /**
   * Recursive subtree read — Prisma has no native recursive CTE, so this goes through $queryRaw
   * with a tagged template (parameterised, never string-concatenated SQL). Returns the root plus
   * every descendant, each annotated with its depth relative to the root (0 = root).
   */
  function subtree(rootId, includeInactive = false) {
    return cache.wrap(`locations:subtree:${rootId}:${includeInactive}`, cacheOpts, async () => {
      await getExisting(rootId);
      const activeFilter = includeInactive ? Prisma.empty : Prisma.sql`WHERE is_active = true`;
      const rows = await prisma.$queryRaw`
        WITH RECURSIVE tree AS (
          SELECT *, 0 AS depth FROM locations WHERE id = ${rootId}
          UNION ALL
          SELECT l.*, t.depth + 1 AS depth
          FROM locations l
          INNER JOIN tree t ON l.parent_id = t.id
        )
        SELECT * FROM tree
        ${activeFilter}
        ORDER BY depth ASC, name ASC
      `;
      return rows.map(mapRow);
    });
  }

  async function resolveWarehouseAndParent(warehouseId, parentId) {
    if (parentId) {
      const parent = await getExisting(parentId);
      if (warehouseId && warehouseId !== parent.warehouseId) {
        throw badRequest("warehouseId does not match the parent location's warehouse");
      }
      return { warehouseId: parent.warehouseId, parentId: parent.id };
    }
    if (!warehouseId) throw badRequest('Either warehouseId or parentId is required');
    await warehouses.getExisting(warehouseId);
    return { warehouseId, parentId: null };
  }

  async function insertLocation(warehouseId, parentId, dto) {
    try {
      const created = await prisma.location.create({
        data: {
          warehouseId,
          parentId,
          name: dto.name,
          code: dto.code,
          locationType: dto.locationType,
          description: dto.description,
        },
      });
      await structureChanged();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function create(dto) {
    const { warehouseId, parentId } = await resolveWarehouseAndParent(dto.warehouseId ?? undefined, dto.parentId ?? undefined);
    return insertLocation(warehouseId, parentId, dto);
  }

  async function addChild(parentId, dto) {
    const parent = await getExisting(parentId);
    return insertLocation(parent.warehouseId, parent.id, dto);
  }

  async function update(id, dto) {
    try {
      const updated = await prisma.location.update({
        where: { id },
        data: {
          name: dto.name ?? undefined,
          code: dto.code ?? undefined,
          locationType: dto.locationType ?? undefined,
          description: dto.description,
          isActive: dto.isActive ?? undefined,
        },
      });
      await structureChanged();
      return updated;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function assertNoCycle(locationId, proposedParentId) {
    let currentId = proposedParentId;
    const visited = new Set();
    while (currentId) {
      if (currentId === locationId) {
        throw conflict('Cannot assign this parent: it would create a cycle in the location tree');
      }
      if (visited.has(currentId)) break;
      visited.add(currentId);
      const parent = await prisma.location.findUnique({ where: { id: currentId }, select: { parentId: true } });
      currentId = parent?.parentId ?? null;
    }
  }

  async function move(id, dto) {
    const location = await getExisting(id);

    let moved;
    if (dto.parentId === null) {
      moved = await prisma.location.update({ where: { id }, data: { parentId: null } });
    } else {
      if (dto.parentId === id) throw badRequest('A location cannot be its own parent');
      const newParent = await getExisting(dto.parentId);
      if (newParent.warehouseId !== location.warehouseId) {
        throw badRequest('Cannot move a location to a parent in a different warehouse');
      }
      await assertNoCycle(id, dto.parentId);
      moved = await prisma.location.update({ where: { id }, data: { parentId: dto.parentId } });
    }
    await structureChanged();
    return moved;
  }

  async function remove(id) {
    await getExisting(id);
    // Structural reference data is soft-deleted (rule 10) — inventory_balances keep a valid reference.
    const removed = await prisma.location.update({ where: { id }, data: { isActive: false } });
    await structureChanged();
    return removed;
  }

  /** "Create N levels" convenience: plain sibling inserts under `parentId`. Deliberately unbounded (rule 5). */
  async function generateLevels(parentId, dto) {
    const parent = await getExisting(parentId);

    const locationType = dto.locationType ?? 'LEVEL';
    const namePrefix = dto.namePrefix ?? 'Level';
    const codePrefix = dto.codePrefix ?? locationType.charAt(0).toUpperCase();
    const startIndex = dto.startIndex ?? 1;

    const rows = Array.from({ length: dto.count }, (_, offset) => {
      const n = startIndex + offset;
      return {
        warehouseId: parent.warehouseId,
        parentId: parent.id,
        name: `${namePrefix} ${n}`,
        code: `${parent.code}-${codePrefix}${n}`,
        locationType,
      };
    });

    try {
      const created = await prisma.$transaction(rows.map((data) => prisma.location.create({ data })));
      await structureChanged();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  return {
    findAll,
    findOne: getExisting,
    getExisting,
    assertLeaf,
    children,
    subtree,
    create,
    addChild,
    update,
    move,
    remove,
    generateLevels,
  };
}

module.exports = { createLocationsService };
