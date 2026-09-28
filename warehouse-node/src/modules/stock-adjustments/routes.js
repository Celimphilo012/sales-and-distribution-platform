'use strict';

const { AdjustmentBucket, AdjustmentDirection, AdjustmentStatus } = require('../../core/enums');
const { obj, nonEmpty, str, num, uuid, opt, enumOf, uuidParams } = require('../../core/schema');
const { notFound } = require('../../core/errors');
const { compileValidator } = require('../../core/validate');
const { saveImageUpload, deleteImageFile, sendImageFile } = require('../../core/uploads');

const ADJUSTMENT_PHOTO_SUBDIR = 'adjustments';

const listQuery = obj({ status: enumOf(AdjustmentStatus) });
const approveBody = obj({ reviewNote: opt(str()) });
const rejectBody = obj({ reviewNote: nonEmpty() }, ['reviewNote']);

const createSchema = obj(
  {
    productId: uuid,
    locationId: uuid,
    bucket: enumOf(AdjustmentBucket),
    delta: num({ multipleOf: 0.001, exclusiveMinimum: 0 }),
    direction: enumOf(AdjustmentDirection),
    reason: nonEmpty(),
    reference: opt(str()),
  },
  ['productId', 'locationId', 'bucket', 'delta', 'direction', 'reason'],
);
// The create route accepts JSON OR multipart/form-data (carrying an optional photo), so it validates
// by hand; multipart fields all arrive as strings and are coerced (e.g. delta "5" -> 5) like the JSON path.
const validateCreate = compileValidator(createSchema);

// Mounted at /inventory/adjustments. Two-step: a request never moves stock; approval (by a DIFFERENT
// user) is what writes the ledger.
function stockAdjustmentsRoutes(app) {
  const { stockAdjustments, otp } = app.services;
  const { authenticate, requirePermissions } = app;

  app.get(
    '/',
    { onRequest: [authenticate, requirePermissions('inventory.view')], schema: { querystring: listQuery } },
    async (request) => stockAdjustments.findAll(request.query, request.user.id),
  );

  app.post(
    '/',
    { onRequest: [authenticate, requirePermissions('inventory.adjust.request')] },
    async (request, res) => {
      let dto;
      let photoPath;

      if (request.is('multipart/form-data')) {
        const upload = await saveImageUpload(request, res, ADJUSTMENT_PHOTO_SUBDIR, {
          fieldName: 'photo',
          required: false,
          invalidTypeMessage: 'Photo must be a JPEG, PNG, or WebP image',
        });
        photoPath = upload.filename;
        dto = { ...upload.fields };
      } else {
        dto = { ...(request.body ?? {}) };
      }

      try {
        validateCreate(dto);
      } catch (error) {
        if (photoPath) deleteImageFile(ADJUSTMENT_PHOTO_SUBDIR, photoPath); // don't orphan the upload
        throw error;
      }

      let adjustment;
      try {
        adjustment = await stockAdjustments.createRequest({ ...dto, requestedBy: request.user.id, photoPath });
      } catch (error) {
        if (photoPath) deleteImageFile(ADJUSTMENT_PHOTO_SUBDIR, photoPath);
        throw error;
      }

      request.auditEntity = 'stock_adjustments';
      request.auditEntityId = adjustment.id;
      // The file itself isn't meaningful in an audit trail — record the parsed DTO plus whether a photo came with it.
      request.auditBody = { ...dto, hasPhoto: Boolean(photoPath) };
      return adjustment;
    },
  );

  app.get(
    '/:id/photo',
    {
      onRequest: [authenticate, requirePermissions('inventory.view')],
      schema: { params: uuidParams('id') },
    },
    async (request, res) => {
      const adjustment = await stockAdjustments.getAccessible(request.params.id, request.user.id);
      if (!adjustment.photoPath) throw notFound(`Stock adjustment ${request.params.id} has no photo attached`);
      return sendImageFile(request, res, ADJUSTMENT_PHOTO_SUBDIR, adjustment.photoPath);
    },
  );

  // Approving/rejecting is confirmed with a one-time code (catalog/otp-actions.js).
  const review = (action, verb, bodySchema, run) => {
    app.post(
      `/:id/${action}`,
      {
        onRequest: [authenticate, requirePermissions('inventory.adjust.approve')],
        preHandler: [otp.requireOtp(`stock_adjustment.${action}`)],
        schema: { params: uuidParams('id'), body: bodySchema },
      },
      async (request) => {
        request.auditEntity = 'stock_adjustments';
        request.auditOldValue = await stockAdjustments.getExisting(request.params.id);
        request.auditAction = verb;
        return run(request);
      },
    );
  };

  review('approve', 'APPROVE', approveBody, (request) =>
    stockAdjustments.approve(request.params.id, request.user.id, request.body.reviewNote ?? undefined),
  );
  review('reject', 'REJECT', rejectBody, (request) =>
    stockAdjustments.reject(request.params.id, request.user.id, request.body.reviewNote),
  );
}

module.exports = stockAdjustmentsRoutes;
