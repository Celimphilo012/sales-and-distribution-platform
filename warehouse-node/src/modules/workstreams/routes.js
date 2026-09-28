'use strict';

const { obj, nonEmpty, str, bool, uuid, opt, boolQuery, uuidParams } = require('../../core/schema');
const { saveImageUpload, sendImageFile } = require('../../core/uploads');
const { WORKSTREAM_IMAGE_UPLOAD_SUBDIR } = require('./service');

const listQuery = obj({ warehouseId: uuid, includeInactive: boolQuery });

const createBody = obj(
  {
    warehouseId: uuid,
    name: nonEmpty(),
    code: nonEmpty(),
    description: opt(str()),
    imageUrl: opt(str()),
    contactName: opt(str()),
    contactEmail: opt(str()),
    contactPhone: opt(str()),
  },
  ['warehouseId', 'name', 'code'],
);

const updateBody = obj({
  name: opt(nonEmpty()),
  code: opt(nonEmpty()),
  description: opt(str()),
  imageUrl: opt(str()),
  contactName: opt(str()),
  contactEmail: opt(str()),
  contactPhone: opt(str()),
  isActive: opt(bool),
});

// Catalogue-organisation layer (Warehouse -> Workstream -> Category -> sub-category -> Product):
// catalogue.view to read, workstreams.manage to create/edit/deactivate the records themselves.
function workstreamsRoutes(app) {
  const { workstreams, otp } = app.services;
  const view = [app.authenticate, app.requirePermissions('catalogue.view')];
  const manage = [app.authenticate, app.requirePermissions('workstreams.manage')];
  const idParams = { params: uuidParams('id') };
  const deactivateOtp = otp.requireOtp('workstream.deactivate', { when: (req) => req.body.isActive === false });

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) =>
    workstreams.findAll(request.query, request.user.id),
  );

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) =>
    workstreams.findOne(request.params.id, request.user.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) =>
    workstreams.create(request.body, request.user.id),
  );

  app.patch(
    '/:id',
    { onRequest: manage, preHandler: [deactivateOtp], schema: { ...idParams, body: updateBody } },
    async (request) => {
      request.auditOldValue = await workstreams.getExisting(request.params.id);
      return workstreams.update(request.params.id, request.body, request.user.id);
    },
  );

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('workstream.deactivate')], schema: idParams },
    async (request) => {
      request.auditOldValue = await workstreams.getExisting(request.params.id);
      request.auditAction = 'DEACTIVATE';
      return workstreams.remove(request.params.id, request.user.id);
    },
  );

  app.post('/:id/image/upload', { onRequest: manage, schema: idParams }, async (request, res) => {
    const { id } = request.params;
    request.auditOldValue = await workstreams.getAccessible(id, request.user.id);
    const { filename } = await saveImageUpload(request, res, WORKSTREAM_IMAGE_UPLOAD_SUBDIR);
    request.auditBody = { imagePath: filename };
    return workstreams.uploadImage(id, filename, request.user.id);
  });

  app.delete(
    '/:id/image',
    { onRequest: manage, preHandler: [otp.requireOtp('workstream_image.delete')], schema: idParams },
    async (request) => {
      request.auditOldValue = await workstreams.getExisting(request.params.id);
      return workstreams.removeImage(request.params.id, request.user.id);
    },
  );

  app.get('/:id/image/file', { onRequest: view, schema: idParams }, async (request, res) => {
    const filename = await workstreams.getImageFilename(request.params.id, request.user.id);
    return sendImageFile(request, res, WORKSTREAM_IMAGE_UPLOAD_SUBDIR, filename);
  });
}

module.exports = workstreamsRoutes;
