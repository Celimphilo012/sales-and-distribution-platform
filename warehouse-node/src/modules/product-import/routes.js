'use strict';

const { obj, uuid } = require('../../core/schema');
const { badRequest } = require('../../core/errors');
const { HANDLED } = require('../../core/http');
const { readMultipart } = require('../../core/uploads');

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024; // a spreadsheet import has no business being bigger than this

/** Reads the single `file` part of a multipart request into memory (never touches disk). */
async function readUploadedFile(request, res) {
  await readMultipart(request, res, { fieldName: 'file', maxBytes: MAX_UPLOAD_BYTES });
  return request.file ? { buffer: request.file.buffer, originalname: request.file.originalname } : undefined;
}

// Mounted at /products/import. Supplements manual product creation; preview is session-staged and
// confirm re-validates defensively before writing anything.
function productImportRoutes(app) {
  const { productImport } = app.services;
  const manage = [app.authenticate, app.requirePermissions('products.manage')];

  app.get('/template', { onRequest: manage }, async (request, res) => {
    const buffer = await productImport.buildTemplate(request.user.id);
    res
      .status(200)
      .set({
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': 'attachment; filename="product-import-template.xlsx"',
      })
      .send(buffer);
    return HANDLED;
  });

  app.post('/preview', { onRequest: manage }, async (request, res) => {
    const file = await readUploadedFile(request, res);
    if (!file) throw badRequest('No file uploaded — attach a .xlsx or .csv file as "file"');

    const result = await productImport.preview(file, request.user.id);
    request.auditEntity = 'products';
    request.auditEntityId = result.importSessionId;
    request.auditAction = 'IMPORT_PREVIEW';
    // The request has no JSON body (it is a multipart upload); record the summary as the audit newValue
    // so the preview leaves a trace even if it is never confirmed.
    request.auditBody = { fileName: file.originalname, summary: result.summary };
    return result;
  });

  app.post(
    '/confirm',
    { onRequest: manage, schema: { body: obj({ importSessionId: uuid }, ['importSessionId']) } },
    async (request) => {
      const result = await productImport.confirm(request.body.importSessionId, request.user.id);
      request.auditEntity = 'products';
      request.auditEntityId = request.body.importSessionId;
      request.auditAction = 'IMPORT';
      request.auditBody = {
        fileName: result.fileName,
        created: result.created,
        updated: result.updated,
        failedCount: result.failed.length,
        failed: result.failed,
      };
      return result;
    },
  );
}

module.exports = productImportRoutes;
