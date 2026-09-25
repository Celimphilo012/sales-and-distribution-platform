'use strict';

const { notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { deleteImageFile } = require('../../core/uploads');

const PRODUCT_IMAGE_UPLOAD_SUBDIR = 'products';

function createProductImagesService({ prisma, cache, products }) {
  // Images are embedded in every product read, so any image change invalidates the catalogue.
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  async function findAll(productId) {
    await products.assertExists(productId);
    return prisma.productImage.findMany({ where: { productId }, orderBy: { sortOrder: 'asc' } });
  }

  async function getExisting(productId, imageId) {
    const image = await prisma.productImage.findUnique({ where: { id: imageId } });
    if (!image || image.productId !== productId) {
      throw notFound(`Image ${imageId} not found for product ${productId}`);
    }
    return image;
  }

  async function createRow(productId, source, dto) {
    await products.assertExists(productId);

    const image = await prisma.$transaction(async (tx) => {
      if (dto.isPrimary) await tx.productImage.updateMany({ where: { productId }, data: { isPrimary: false } });
      return tx.productImage.create({
        data: { productId, ...source, sortOrder: dto.sortOrder ?? 0, isPrimary: dto.isPrimary ?? false },
      });
    });
    await invalidate();
    return image;
  }

  const create = (productId, dto) => createRow(productId, { url: dto.url }, dto);

  /** Same as create(), but for a file uploaded from device storage instead of a pasted URL. */
  const createFromUpload = (productId, storedFilename, dto) =>
    createRow(productId, { storagePath: storedFilename }, dto);

  /** Stored filename of an uploaded image, for GET .../file. 404s for a URL-based image (nothing on disk). */
  async function getStoredFilename(productId, imageId) {
    const image = await getExisting(productId, imageId);
    if (!image.storagePath) throw notFound(`Image ${imageId} has no uploaded file`);
    return image.storagePath;
  }

  async function update(productId, imageId, dto) {
    const existing = await getExisting(productId, imageId);

    // Switching an uploaded image over to a pasted URL — keep the url/storagePath invariant
    // (exactly one set) and clean up the now-orphaned file on disk.
    const clearingStoragePath = dto.url !== undefined && existing.storagePath;

    const updated = await prisma.$transaction(async (tx) => {
      if (dto.isPrimary) {
        await tx.productImage.updateMany({
          where: { productId, id: { not: imageId } },
          data: { isPrimary: false },
        });
      }
      return tx.productImage.update({
        where: { id: imageId },
        data: {
          url: dto.url,
          storagePath: clearingStoragePath ? null : undefined,
          sortOrder: dto.sortOrder ?? undefined,
          isPrimary: dto.isPrimary ?? undefined,
        },
      });
    });

    if (clearingStoragePath) deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    await invalidate();
    return updated;
  }

  async function remove(productId, imageId) {
    const existing = await getExisting(productId, imageId);
    // Media rows are not historical/reference data — hard delete is fine.
    await prisma.productImage.delete({ where: { id: imageId } });
    if (existing.storagePath) deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    await invalidate();
    return { id: imageId, deleted: true };
  }

  return { findAll, getExisting, create, createFromUpload, getStoredFilename, update, remove };
}

module.exports = { createProductImagesService, PRODUCT_IMAGE_UPLOAD_SUBDIR };
