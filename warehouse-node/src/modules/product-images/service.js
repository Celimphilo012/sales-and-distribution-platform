'use strict';

const { notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols } = require('../../core/models');
const { deleteImageFile } = require('../../core/uploads');

const PRODUCT_IMAGE_UPLOAD_SUBDIR = 'products';

function createProductImagesService({ db, models, cache, products }) {
  // Images are embedded in every product read, so any image change invalidates the catalogue.
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  // Every operation takes the acting user: images belong to a product, and the product to a
  // warehouse the user must have access to (modules/access).
  async function findAll(productId, userId) {
    await products.assertAccessible(productId, userId);
    return db.query(
      `SELECT ${cols('productImage', 'i')} FROM product_images i WHERE i.product_id = ? ORDER BY i.sort_order ASC`,
      [productId],
    );
  }

  async function getExisting(productId, imageId) {
    const image = await models.findById('productImage', imageId);
    if (!image || image.productId !== productId) {
      throw notFound(`Image ${imageId} not found for product ${productId}`);
    }
    return image;
  }

  async function createRow(productId, source, dto, userId) {
    await products.assertAccessible(productId, userId);

    const image = await db.transaction(async (tx) => {
      if (dto.isPrimary) await db.exec('UPDATE product_images SET is_primary = false WHERE product_id = ?', [productId], tx);
      return models.insert(
        'productImage',
        { productId, ...source, sortOrder: dto.sortOrder ?? 0, isPrimary: dto.isPrimary ?? false },
        tx,
      );
    });
    await invalidate();
    return image;
  }

  const create = (productId, dto, userId) => createRow(productId, { url: dto.url }, dto, userId);

  /** Same as create(), but for a file uploaded from device storage instead of a pasted URL. */
  const createFromUpload = (productId, storedFilename, dto, userId) =>
    createRow(productId, { storagePath: storedFilename }, dto, userId);

  /** Stored filename of an uploaded image, for GET .../file. 404s for a URL-based image (nothing on disk). */
  async function getStoredFilename(productId, imageId, userId) {
    await products.assertAccessible(productId, userId);
    const image = await getExisting(productId, imageId);
    if (!image.storagePath) throw notFound(`Image ${imageId} has no uploaded file`);
    return image.storagePath;
  }

  async function update(productId, imageId, dto, userId) {
    await products.assertAccessible(productId, userId);
    const existing = await getExisting(productId, imageId);

    // Switching an uploaded image over to a pasted URL — keep the url/storagePath invariant
    // (exactly one set) and clean up the now-orphaned file on disk.
    const clearingStoragePath = dto.url !== undefined && existing.storagePath;

    const updated = await db.transaction(async (tx) => {
      if (dto.isPrimary) {
        await db.exec('UPDATE product_images SET is_primary = false WHERE product_id = ? AND id <> ?', [productId, imageId], tx);
      }
      return models.update(
        'productImage',
        imageId,
        {
          url: dto.url,
          storagePath: clearingStoragePath ? null : undefined,
          sortOrder: dto.sortOrder ?? undefined,
          isPrimary: dto.isPrimary ?? undefined,
        },
        'Image',
        tx,
      );
    });

    if (clearingStoragePath) deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    await invalidate();
    return updated;
  }

  async function remove(productId, imageId, userId) {
    await products.assertAccessible(productId, userId);
    const existing = await getExisting(productId, imageId);
    // Media rows are not historical/reference data — hard delete is fine.
    await db.exec('DELETE FROM product_images WHERE id = ?', [imageId]);
    if (existing.storagePath) deleteImageFile(PRODUCT_IMAGE_UPLOAD_SUBDIR, existing.storagePath);
    await invalidate();
    return { id: imageId, deleted: true };
  }

  return { findAll, getExisting, create, createFromUpload, getStoredFilename, update, remove };
}

module.exports = { createProductImagesService, PRODUCT_IMAGE_UPLOAD_SUBDIR };
