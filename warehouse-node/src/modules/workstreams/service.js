'use strict';

const { Prisma } = require('@prisma/client');
const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { deleteImageFile } = require('../../core/uploads');

const WORKSTREAM_IMAGE_UPLOAD_SUBDIR = 'workstreams';

function createWorkstreamsService({ prisma, cache, config, warehouses, workstreamManagers }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  function translateUniqueViolation(error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return conflict('A workstream with this code already exists in this warehouse');
    }
    return error;
  }

  /** An empty assignment set means "unscoped" — no restriction. */
  async function scopeFilter(viewerId) {
    if (!viewerId) return {};
    const assignedIds = await workstreamManagers.getAssignedWorkstreamIds(viewerId);
    return assignedIds.length === 0 ? {} : { id: { in: assignedIds } };
  }

  /**
   * [viewerId], when given, narrows the result to the workstream(s) that viewer is assigned to
   * manage — a no-op for an unscoped user. Omitted by internal callers (dashboard count, product
   * import, seeds) that intentionally need the full set.
   */
  async function findAll(query = {}, viewerId) {
    const scope = await scopeFilter(viewerId);
    const key = `workstreams:list:${query.warehouseId ?? '-'}:${query.includeInactive ? 'all' : 'active'}:${scope.id ? scope.id.in.join(',') : '*'}`;
    return cache.wrap(key, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] }, () =>
      prisma.workstream.findMany({
        where: {
          warehouseId: query.warehouseId,
          isActive: query.includeInactive ? undefined : true,
          ...scope,
        },
        orderBy: { name: 'asc' },
      }),
    );
  }

  // Never cached: writers (and audit old-values) must see the row as it is right now.
  async function getExisting(id) {
    const workstream = await prisma.workstream.findUnique({ where: { id } });
    if (!workstream) throw notFound(`Workstream ${id} not found`);
    return workstream;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  const countActive = () => prisma.workstream.count({ where: { isActive: true } });

  /** 403s if the viewer is scoped and this workstream isn't one of theirs (single-item counterpart to findAll's filtering). */
  async function findOne(id, viewerId) {
    const workstream = await getExisting(id);
    if (viewerId) await workstreamManagers.assertScopedAccess(viewerId, id);
    return workstream;
  }

  async function create(dto) {
    await warehouses.getExisting(dto.warehouseId);
    try {
      const created = await prisma.workstream.create({
        data: {
          warehouseId: dto.warehouseId,
          name: dto.name,
          code: dto.code,
          description: dto.description,
          imageUrl: dto.imageUrl,
          contactName: dto.contactName,
          contactEmail: dto.contactEmail,
          contactPhone: dto.contactPhone,
        },
      });
      await invalidate();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function update(id, dto) {
    const existing = await getExisting(id);

    // Setting an external URL replaces any previously uploaded file — keep the imageUrl/imagePath
    // invariant (at most one set) and clean up the now-orphaned file on disk.
    const clearingImagePath = dto.imageUrl !== undefined && existing.imagePath;

    let updated;
    try {
      updated = await prisma.workstream.update({
        where: { id },
        data: {
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
      });
    } catch (error) {
      throw translateUniqueViolation(error);
    }

    if (clearingImagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Uploads a device-storage image, replacing any existing url/uploaded image. */
  async function uploadImage(id, storedFilename) {
    const existing = await getExisting(id);
    const updated = await prisma.workstream.update({
      where: { id },
      data: { imagePath: storedFilename, imageUrl: null },
    });
    if (existing.imagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Clears whichever image (URL or uploaded file) is currently set. */
  async function removeImage(id) {
    const existing = await getExisting(id);
    const updated = await prisma.workstream.update({ where: { id }, data: { imageUrl: null, imagePath: null } });
    if (existing.imagePath) deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    await invalidate();
    return updated;
  }

  /** Stored filename of the uploaded image, for GET :id/image/file. 404s when there is none. */
  async function getImageFilename(id) {
    const workstream = await getExisting(id);
    if (!workstream.imagePath) throw notFound(`Workstream ${id} has no uploaded image`);
    return workstream.imagePath;
  }

  async function remove(id) {
    await getExisting(id);
    // Catalogue-organisation reference data is soft-deleted (rule 10).
    const removed = await prisma.workstream.update({ where: { id }, data: { isActive: false } });
    await invalidate();
    return removed;
  }

  return {
    findAll,
    findOne,
    getExisting,
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
