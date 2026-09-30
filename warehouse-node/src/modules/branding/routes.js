'use strict';

const { notFound } = require('../../core/errors');
const { obj, str } = require('../../core/schema');
const { saveImageUpload, sendImageFile } = require('../../core/uploads');
const { BRANDING_UPLOAD_SUBDIR } = require('./service');

/**
 * Report branding (Settings → Report branding). Reading it is open to every signed-in user —
 * anyone who can export a report prints the logo — while changing it needs `settings.manage`.
 */
function brandingRoutes(app) {
  const { branding } = app.services;
  const read = [app.authenticate];
  const manage = [app.authenticate, app.requirePermissions('settings.manage')];

  app.get('/', { onRequest: read }, async () => branding.view());

  app.put(
    '/',
    { onRequest: manage, schema: { body: obj({ companyName: str({ maxLength: 120 }) }, ['companyName']) } },
    async (request) => {
      request.auditEntity = 'app_settings';
      request.auditEntityId = 'branding';
      request.auditOldValue = await branding.view();
      return branding.setCompanyName(request.body.companyName, request.user.id);
    },
  );

  app.post('/logo', { onRequest: manage }, async (request, res) => {
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'branding';
    const { filename } = await saveImageUpload(request, res, BRANDING_UPLOAD_SUBDIR, {
      invalidTypeMessage: 'The logo must be a PNG, JPEG or WebP image',
    });
    request.auditBody = { logo: filename };
    res.status(200);
    return branding.setLogo(filename, request.user.id);
  });

  app.delete('/logo', { onRequest: manage }, async (request) => {
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'branding';
    request.auditAction = 'RESET_LOGO';
    return branding.clearLogo(request.user.id);
  });

  app.get('/logo', { onRequest: read }, async (request, res) => {
    const filename = await branding.logoFilename();
    if (!filename) throw notFound('No logo has been uploaded');
    return sendImageFile(request, res, BRANDING_UPLOAD_SUBDIR, filename);
  });
}

module.exports = brandingRoutes;
