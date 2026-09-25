'use strict';

const { obj, uuid } = require('../../core/schema');
const { badRequest } = require('../../core/errors');

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024; // a spreadsheet import has no business being bigger than this

/** Reads the single `file` part of a multipart request into memory (never touches disk). */
async function readUploadedFile(request) {
  let file;
  for await (const part of request.parts({ limits: { fileSize: MAX_UPLOAD_BYTES } })) {
    if (part.type !== 'file') {
      continue; // text fields are irrelevant to this endpoint
    }
    if (part.fieldname !== 'file' || file) {
      part.file.resume();
      throw badRequest(`Upload rejected: Unexpected field "${part.fieldname}"`);
    }
    const buffer = await part.toBuffer(); // throws FST_REQ_FILE_TOO_LARGE past the limit
    file = { buffer, originalname: part.filename };
  }
  return file;
}

// Mounted at /products/import. Supplements manual product creation; preview is session-staged and
// confirm re-validates defensively before writing anything.
async function productImportRoutes(app) {
  const { productImport } = app.services;
  const manage = [app.authenticate, app.requirePermissions('products.manage')];

  app.get('/template', { onRequest: manage }, async (request, reply) => {
    const buffer = await productImport.buildTemplate(request.user.id);
    return reply
      .header('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      .header('Content-Disposition', 'attachment; filename="product-import-template.xlsx"')
      .code(200)
      .send(buffer);
  });

  app.post('/preview', { onRequest: manage }, async (request) => {
    const file = await readUploadedFile(request);
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
