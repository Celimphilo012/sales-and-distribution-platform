'use strict';

const { notFound } = require('../../core/errors');
const { obj, str } = require('../../core/schema');
const { saveImageUpload, sendImageFile } = require('../../core/uploads');
const { BRANDING_UPLOAD_SUBDIR } = require('./service');

/**
 * Company branding (Settings → Branding): the name and logo on report exports, the browser tab
 * (favicon + title), the top bar and the sign-in page. Reading it is PUBLIC — the sign-in page
 * shows it before anyone is signed in, and a company's name and logo are not secret — while
 * changing it needs `settings.manage` (the system administrator).
 */
function brandingRoutes(app) {
  const { branding } = app.services;
  const manage = [app.authenticate, app.requirePermissions('settings.manage')];

  app.get('/', async () => branding.view());

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

  app.get('/logo', async (request, res) => {
    const filename = await branding.logoFilename();
    if (!filename) throw notFound('No logo has been uploaded');
    return sendImageFile(request, res, BRANDING_UPLOAD_SUBDIR, filename);
  });
}

module.exports = brandingRoutes;
