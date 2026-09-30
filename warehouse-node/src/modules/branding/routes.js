'use strict';

const { notFound } = require('../../core/errors');
const { obj, str, opt } = require('../../core/schema');
const { saveImageUpload, sendImageFile } = require('../../core/uploads');
const { BRANDING_UPLOAD_SUBDIR } = require('./service');
const { BRAND_FONTS } = require('./fonts');

/**
 * Company branding (Settings → Branding): the name, tagline, brand colour and logo on report
 * exports, the browser tab (favicon + title + theme colour), the console's accent colour, the top
 * bar and the sign-in page. Reading it is PUBLIC — the sign-in page
 * shows it before anyone is signed in, and a company's name and logo are not secret — while
 * changing it needs `settings.manage` (the system administrator).
 */
// Any subset may be sent; a field left out is unchanged. `brandColor` null (or '') returns to the
// built-in accent; `tagline` null (or '') removes it.
const fontName = opt(str({ enum: [...Object.keys(BRAND_FONTS), ''] }));
const line = (maxLength) => opt(str({ maxLength }));
const identityBody = {
  companyName: str({ maxLength: 120 }),
  tagline: line(80),
  brandColor: opt(str({ pattern: '^(#[0-9A-Fa-f]{6})?$' })),
  headingFont: fontName,
  bodyFont: fontName,
  // The letterhead on PDF documents and the contact line under every email.
  letterhead: opt(
    obj({
      address: line(300),
      phone: line(60),
      email: line(120),
      website: line(120),
      registration: line(160),
      footer: line(240),
    }),
  ),
  emailSignature: line(1000),
};

function brandingRoutes(app) {
  const { branding } = app.services;
  const manage = [app.authenticate, app.requirePermissions('settings.manage')];

  app.get('/', async () => branding.view());

  app.put(
    '/',
    { onRequest: manage, schema: { body: { ...obj(identityBody), minProperties: 1 } } },
    async (request) => {
      request.auditEntity = 'app_settings';
      request.auditEntityId = 'branding';
      request.auditOldValue = await branding.view();
      return branding.setIdentity(request.body, request.user.id);
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
