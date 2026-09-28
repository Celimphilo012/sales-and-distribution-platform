'use strict';

const { obj, nonEmpty, int, bool, opt, uuidParams } = require('../../core/schema');
const { saveImageUpload, sendImageFile } = require('../../core/uploads');
const { PRODUCT_IMAGE_UPLOAD_SUBDIR } = require('./service');
const { badRequest } = require('../../core/errors');

const createBody = obj({ url: nonEmpty(), sortOrder: opt(int({ minimum: 0 })), isPrimary: opt(bool) }, ['url']);
const updateBody = obj({ url: opt(nonEmpty()), sortOrder: opt(int({ minimum: 0 })), isPrimary: opt(bool) });

/** Multipart text fields arrive as strings; parse them the way the JSON body would have been. */
function parseUploadFields(fields) {
  const sortOrder = fields.sortOrder === undefined || fields.sortOrder === '' ? undefined : Number(fields.sortOrder);
  if (sortOrder !== undefined && (!Number.isInteger(sortOrder) || sortOrder < 0)) {
    throw badRequest(['sortOrder must not be less than 0', 'sortOrder must be an integer number']);
  }
  const isPrimary = fields.isPrimary === undefined ? undefined : ['true', '1', 'on'].includes(String(fields.isPrimary).toLowerCase());
  return { sortOrder, isPrimary };
}

// Mounted at /products/:productId/images
function productImagesRoutes(app) {
  const { productImages, products, otp } = app.services;
  const view = [app.authenticate, app.requirePermissions('catalogue.view')];
  const manage = [app.authenticate, app.requirePermissions('products.manage')];
  const productParams = { params: uuidParams('productId') };
  const imageParams = { params: uuidParams('productId', 'imageId') };

  app.get('/', { onRequest: view, schema: productParams }, async (request) =>
    productImages.findAll(request.params.productId, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { ...productParams, body: createBody } }, async (request) => {
    request.auditEntity = 'product_images';
    const image = await productImages.create(request.params.productId, request.body, request.user.id);
    request.auditEntityId = image.id;
    return image;
  });

  app.post('/upload', { onRequest: manage, schema: productParams }, async (request, res) => {
    request.auditEntity = 'product_images';
    // Check access BEFORE writing anything to disk, so a refused upload leaves no orphan file.
    await products.assertAccessible(request.params.productId, request.user.id);
    const { filename, fields } = await saveImageUpload(request, res, PRODUCT_IMAGE_UPLOAD_SUBDIR);
    const dto = parseUploadFields(fields);
    request.auditBody = dto;
    const image = await productImages.createFromUpload(request.params.productId, filename, dto, request.user.id);
    request.auditEntityId = image.id;
    return image;
  });

  app.get('/:imageId/file', { onRequest: view, schema: imageParams }, async (request, res) => {
    const filename = await productImages.getStoredFilename(request.params.productId, request.params.imageId, request.user.id);
    return sendImageFile(request, res, PRODUCT_IMAGE_UPLOAD_SUBDIR, filename);
  });

  app.patch('/:imageId', { onRequest: manage, schema: { ...imageParams, body: updateBody } }, async (request) => {
    request.auditEntity = 'product_images';
    request.auditOldValue = await productImages.getExisting(request.params.productId, request.params.imageId);
    return productImages.update(request.params.productId, request.params.imageId, request.body, request.user.id);
  });

  app.delete(
    '/:imageId',
    { onRequest: manage, preHandler: [otp.requireOtp('product_image.delete')], schema: imageParams },
    async (request) => {
      request.auditEntity = 'product_images';
      request.auditOldValue = await productImages.getExisting(request.params.productId, request.params.imageId);
      return productImages.remove(request.params.productId, request.params.imageId, request.user.id);
    },
  );
}

module.exports = productImagesRoutes;
