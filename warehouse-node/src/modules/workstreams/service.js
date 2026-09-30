'use strict';

const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { isUniqueViolation } = require('../../core/db');
const { cols, Where } = require('../../core/models');
const { deleteImageFile } = require('../../core/uploads');

const WORKSTREAM_IMAGE_UPLOAD_SUBDIR = 'workstreams';

function createWorkstreamsService({ db, models, cache, config, access, warehouses, workstreamManagers }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  function translateUniqueViolation(error) {
    return isUniqueViolation(error) ? conflict('A workstream with this code already exists in this warehouse') : error;
  }

  /** The workstream ids a viewer is restricted to, or undefined when unscoped (no restriction). */
  async function scopeIds(viewerId) {
    if (!viewerId) return undefined;
    const assignedIds = await workstreamManagers.getAssignedWorkstreamIds(viewerId);
    return assignedIds.length === 0 ? undefined : assignedIds;
  }

  /**
   * [viewerId], when given, narrows the result to the viewer's warehouses (modules/access), then to
   * the workstream(s) they are assigned to manage — the latter a no-op for an unscoped manager. Omitted by internal callers (dashboard count, product
   * import, seeds) that intentionally need the full set.
   */
  async function findAll(query = {}, viewerId) {
    const [scope, warehouseIds] = await Promise.all([scopeIds(viewerId), access.warehouseScope(viewerId)]);
    const key = `workstreams:list:${query.warehouseId ?? '-'}:${query.includeInactive ? 'all' : 'active'}:${scope ? scope.join(',') : '*'}:${access.scopeKey(warehouseIds)}`;
    const rows = await cache.wrap(key, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] }, () => {
      const where = new Where()
        .eq('w.warehouse_id', query.warehouseId)
        .in('w.warehouse_id', warehouseIds ?? undefined)
        .in('w.id', scope);
      if (!query.includeInactive) where.raw('w.is_active = true');
      return db.query(`SELECT ${cols('workstream', 'w')} FROM workstreams w ${where.sql} ORDER BY w.name ASC`, where.params);
    });
    return attachManagers(rows);
  }

  /**
   * Each workstream's scoped managers as `managers: [{userId, fullName}]` — read fresh (outside the
   * catalogue cache) since assignments change independently of the catalogue.
   */
  async function attachManagers(rows) {
    if (rows.length === 0) return rows;
    const where = new Where().in('wm.workstream_id', rows.map((w) => w.id));
    const links = await db.query(
      `SELECT wm.workstream_id AS workstreamId, u.id AS userId, u.full_name AS fullName
         FROM workstream_managers wm JOIN users u ON u.id = wm.user_id ${where.sql} ORDER BY u.full_name ASC`,
      where.params,
    );
    return rows.map((w) => ({
      ...w,
      managers: links.filter((l) => l.workstreamId === w.id).map(({ userId, fullName }) => ({ userId, fullName })),
    }));
  }

  // Never cached: writers (and audit old-values) must see the row as it is right now.
  const getExisting = (id) => models.getById('workstream', id, 'Workstream');

  /** getExisting + the caller must have access to the workstream's warehouse. */
  async function getAccessible(id, userId) {
    const workstream = await getExisting(id);
    await access.assertWarehouse(userId, workstream.warehouseId);
    return workstream;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary, within the given warehouses (null = all). */
  async function countActive(warehouseIds = null) {
    const where = new Where().raw('is_active = true').in('warehouse_id', warehouseIds ?? undefined);
    return Number((await db.one(`SELECT COUNT(*) AS n FROM workstreams ${where.sql}`, where.params)).n);
  }

  /** 403s if the viewer is scoped and this workstream isn't one of theirs (single-item counterpart to findAll's filtering). */
  async function findOne(id, viewerId) {
    const workstream = await getAccessible(id, viewerId);
    if (viewerId) await workstreamManagers.assertScopedAccess(viewerId, id);
    return workstream;
  }

  async function create(dto, actingUserId) {
    await warehouses.getExisting(dto.warehouseId);
    await access.assertWarehouse(actingUserId, dto.warehouseId);
    try {
      const created = await models.insert('workstream', {
        warehouseId: dto.warehouseId,
        name: dto.name,
        code: dto.code,
        description: dto.description,
        imageUrl: dto.imageUrl,
        contactName: dto.contactName,
        contactEmail: dto.contactEmail,
        contactPhone: dto.contactPhone,
      });
      await invalidate();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function update(id, dto, actingUserId) {
    const existing = await getAccessible(id, actingUserId);

    // Setting an external URL replaces any previously uploaded file — keep the imageUrl/imagePath
    // invariant (at most one set) and clean up the now-orphaned file on disk.
    const clearingImagePath = dto.imageUrl !== undefined && existing.imagePath;

    let updated;
    try {
      updated = await models.update(
        'workstream',
        id,
        {
          name: dto.name ?? undefined,
          code: dto.code ?? undefined,
          description: dto.description,
          imageUrl: dto.imageUrl,
          imagePath: clearingImagePath ? null : undefined,
          contactName: dto.contactName,
          contactEmail: dto.contactEmail,
          contactPhone: dto.contactPhone,
          isActive: dto.isActive ?? undefined,
        },
        'Workstream',
      );
    } catch (error) {
      throw translateUniqueViolation(error);
    }

    if (clearingImagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Uploads a device-storage image, replacing any existing url/uploaded image. */
  async function uploadImage(id, storedFilename, actingUserId) {
    const existing = await getAccessible(id, actingUserId);
    const updated = await models.update('workstream', id, { imagePath: storedFilename, imageUrl: null }, 'Workstream');
    if (existing.imagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Clears whichever image (URL or uploaded file) is currently set. */
  async function removeImage(id, actingUserId) {
    const existing = await getAccessible(id, actingUserId);
    const updated = await models.update('workstream', id, { imageUrl: null, imagePath: null }, 'Workstream');
    if (existing.imagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Stored filename of the uploaded image, for GET :id/image/file. 404s when there is none. */
  async function getImageFilename(id, viewerId) {
    const workstream = await getAccessible(id, viewerId);
    if (!workstream.imagePath) throw notFound(`Workstream ${id} has no uploaded image`);
    return workstream.imagePath;
  }

  async function remove(id, actingUserId) {
    await getAccessible(id, actingUserId);
    // Catalogue-organisation reference data is soft-deleted (rule 10).
    const removed = await models.update('workstream', id, { isActive: false }, 'Workstream');
    await invalidate();
    return removed;
  }

  return {
    findAll,
    findOne,
    getExisting,
    getAccessible,
    countActive,
    create,
    update,
    uploadImage,
    removeImage,
    getImageFilename,
    remove,
  };
}

module.exports = { createWorkstreamsService, WORKSTREAM_IMAGE_UPLOAD_SUBDIR };
