'use strict';

const { badRequest, conflict } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { isUniqueViolation } = require('../../core/db');
const { cols, Where } = require('../../core/models');

/**
 * `viewerId` / `actingUserId` is the signed-in user: reads are narrowed to, and writes checked
 * against, the warehouses they may access (modules/access). No user id = unscoped (internal callers).
 */
function createLocationsService({ db, models, cache, config, warehouses, access }) {
  const cacheOpts = { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.STRUCTURE] };
  const structureChanged = () => cache.invalidate(TAGS.STRUCTURE, TAGS.CATALOGUE, TAGS.STOCK);

  function translateUniqueViolation(error) {
    return isUniqueViolation(error) ? conflict('A location with this code already exists in this warehouse') : error;
  }

  async function findAll(query = {}, viewerId) {
    const scope = await access.warehouseScope(viewerId);
    return cache.wrap(
      `locations:list:${query.warehouseId ?? '-'}:${query.rootOnly ? 'root' : (query.parentId ?? '-')}:${query.includeInactive ? 'all' : 'active'}:${access.scopeKey(scope)}`,
      cacheOpts,
      () => {
        const where = new Where()
          .eq('l.warehouse_id', query.warehouseId)
          .eq('l.parent_id', query.rootOnly ? null : query.parentId)
          .in('l.warehouse_id', scope ?? undefined);
        if (!query.includeInactive) where.raw('l.is_active = true');
        return db.query(`SELECT ${cols('location', 'l')} FROM locations l ${where.sql} ORDER BY l.name ASC`, where.params);
      },
    );
  }

  // Never cached: writers and the leaf check depend on the row as it is right now.
  const getExisting = (id) => models.getById('location', id, 'Location');

  /** getExisting + the caller must have access to the location's warehouse. */
  async function getAccessible(id, userId) {
    const location = await getExisting(id);
    await access.assertWarehouse(userId, location.warehouseId);
    return location;
  }

  /**
   * Stock can only be held at leaf locations: receiving/transfer/adjustment/count locations must
   * have zero children, active or not. Deliberately NOT cached — a stale "leaf" answer would let
   * stock be written to a location that has since gained children. With `userId`, also checks
   * that user may access the location's warehouse (every user-facing stock operation passes it).
   */
  async function assertLeaf(locationId, userId) {
    const location = await getAccessible(locationId, userId);
    const { childCount } = await db.one('SELECT COUNT(*) AS childCount FROM locations WHERE parent_id = ?', [locationId]);
    if (childCount > 0) {
      throw badRequest(
        `Location "${location.name}" (${locationId}) is not a leaf location — it has ${childCount} child location(s). Stock can only be held at leaf locations.`,
      );
    }
    return location;
  }

  // The existence check lives inside the loader: locations are only ever soft-deleted, so once a
  // result is cached the parent cannot vanish, and an unknown id throws (and is never cached).
  async function children(parentId, includeInactive = false, viewerId) {
    await getAccessible(parentId, viewerId);
    return cache.wrap(`locations:children:${parentId}:${includeInactive}`, cacheOpts, () =>
      db.query(
        `SELECT ${cols('location', 'l')} FROM locations l
          WHERE l.parent_id = ? ${includeInactive ? '' : 'AND l.is_active = true'}
          ORDER BY l.name ASC`,
        [parentId],
      ),
    );
  }

  /**
   * Recursive subtree read (a recursive CTE — MySQL 8.0+ / MariaDB 10.2.2+). Returns the root plus
   * every descendant, each annotated with its depth relative to the root (0 = root).
   */
  async function subtree(rootId, includeInactive = false, viewerId) {
    await getAccessible(rootId, viewerId);
    return cache.wrap(`locations:subtree:${rootId}:${includeInactive}`, cacheOpts, async () => {
      const rows = await db.query(
        `WITH RECURSIVE tree AS (
           SELECT l.*, 0 AS depth FROM locations l WHERE l.id = ?
           UNION ALL
           SELECT l.*, t.depth + 1 AS depth
             FROM locations l
             INNER JOIN tree t ON l.parent_id = t.id
         )
         SELECT ${cols('location', 'tree')}, tree.depth AS depth FROM tree
         ${includeInactive ? '' : 'WHERE tree.is_active = true'}
         ORDER BY depth ASC, name ASC`,
        [rootId],
      );
      // A CTE's columns lose their TINYINT(1) width, so is_active arrives as 0/1 rather than a boolean.
      return rows.map((row) => ({ ...row, isActive: Boolean(row.isActive), depth: Number(row.depth) }));
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
      const created = await models.insert('location', {
        warehouseId,
        parentId,
        name: dto.name,
        code: dto.code,
        locationType: dto.locationType,
        description: dto.description,
        capacity: dto.capacity,
      });
      await structureChanged();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function create(dto, actingUserId) {
    const { warehouseId, parentId } = await resolveWarehouseAndParent(dto.warehouseId ?? undefined, dto.parentId ?? undefined);
    await access.assertWarehouse(actingUserId, warehouseId);
    return insertLocation(warehouseId, parentId, dto);
  }

  async function addChild(parentId, dto, actingUserId) {
    const parent = await getAccessible(parentId, actingUserId);
    return insertLocation(parent.warehouseId, parent.id, dto);
  }

  async function update(id, dto, actingUserId) {
    await getAccessible(id, actingUserId);
    try {
      const updated = await models.update(
        'location',
        id,
        {
          name: dto.name ?? undefined,
          code: dto.code ?? undefined,
          locationType: dto.locationType ?? undefined,
          description: dto.description,
          // undefined = unchanged; null clears it.
          capacity: dto.capacity,
          isActive: dto.isActive ?? undefined,
        },
        'Location',
      );
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
      const parent = await db.one('SELECT parent_id AS parentId FROM locations WHERE id = ?', [currentId]);
      currentId = parent?.parentId ?? null;
    }
  }

  async function move(id, dto, actingUserId) {
    const location = await getAccessible(id, actingUserId);

    let moved;
    if (dto.parentId === null) {
      moved = await models.update('location', id, { parentId: null }, 'Location');
    } else {
      if (dto.parentId === id) throw badRequest('A location cannot be its own parent');
      const newParent = await getExisting(dto.parentId);
      if (newParent.warehouseId !== location.warehouseId) {
        throw badRequest('Cannot move a location to a parent in a different warehouse');
      }
      await assertNoCycle(id, dto.parentId);
      moved = await models.update('location', id, { parentId: dto.parentId }, 'Location');
    }
    await structureChanged();
    return moved;
  }

  async function remove(id, actingUserId) {
    await getAccessible(id, actingUserId);
    // Structural reference data is soft-deleted (rule 10) — inventory_balances keep a valid reference.
    const removed = await models.update('location', id, { isActive: false }, 'Location');
    await structureChanged();
    return removed;
  }

  /** "Create N levels" convenience: plain sibling inserts under `parentId`, all-or-nothing. Deliberately unbounded (rule 5). */
  async function generateLevels(parentId, dto, actingUserId) {
    const parent = await getAccessible(parentId, actingUserId);

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
        capacity: dto.capacity ?? undefined,
      };
    });

    try {
      const created = await db.transaction(async (tx) => {
        const out = [];
        for (const data of rows) out.push(await models.insert('location', data, tx));
        return out;
      });
      await structureChanged();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  return {
    findAll,
    findOne: getAccessible,
    getExisting,
    getAccessible,
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
