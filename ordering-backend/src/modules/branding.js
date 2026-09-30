'use strict';

const { notFound } = require('../core/errors');
const { obj, str, opt } = require('../core/schema');
const { saveImageUpload, sendImageFile, deleteImageFile } = require('../core/uploads');

const BRANDING_UPLOAD_SUBDIR = 'branding';
const KEY_COMPANY = 'branding.company';
const KEY_LOGO = 'branding.logo';
const KEY_TAGLINE = 'branding.tagline';
const KEY_COLOR = 'branding.color';
// The brand kit — fonts, letterhead and email signature — as one JSON document, so new kit
// fields can be added without a new settings key each.
const KEY_KIT = 'branding.kit';

const LETTERHEAD_FIELDS = ['address', 'phone', 'email', 'website', 'registration', 'footer'];

/**
 * The approved brand fonts an administrator can choose (Settings → Branding → Typography): Google
 * Fonts the console can load, each with the CSS stack emails fall back to (email clients rarely
 * load web fonts). The console keeps the same list (copied — no shared code, and the same list as
 * the warehouse system's, copied there too).
 */
const BRAND_FONTS = {
  Inter: "'Inter',Arial,Helvetica,sans-serif",
  Roboto: "'Roboto',Arial,Helvetica,sans-serif",
  'Open Sans': "'Open Sans',Arial,Helvetica,sans-serif",
  Lato: "'Lato',Arial,Helvetica,sans-serif",
  Montserrat: "'Montserrat',Arial,Helvetica,sans-serif",
  Poppins: "'Poppins',Arial,Helvetica,sans-serif",
  'Nunito Sans': "'Nunito Sans',Arial,Helvetica,sans-serif",
  'Source Sans 3': "'Source Sans 3','Source Sans Pro',Arial,Helvetica,sans-serif",
  'Work Sans': "'Work Sans',Arial,Helvetica,sans-serif",
  'IBM Plex Sans': "'IBM Plex Sans',Arial,Helvetica,sans-serif",
  'DM Sans': "'DM Sans',Arial,Helvetica,sans-serif",
  Manrope: "'Manrope',Arial,Helvetica,sans-serif",
  Merriweather: "'Merriweather',Georgia,'Times New Roman',serif",
  'Playfair Display': "'Playfair Display',Georgia,'Times New Roman',serif",
  'Source Serif 4': "'Source Serif 4','Source Serif Pro',Georgia,'Times New Roman',serif",
};
const DEFAULT_FONT = 'Inter';

function parseKit(raw) {
  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

/**
 * Company branding (Settings → Branding): the name, tagline, brand colour and logo, plus the brand
 * kit — approved heading / body fonts, the letterhead (address, contacts, registration, footer line)
 * and the email signature. Used for the console's look, the sign-in page, every PDF / Excel report
 * and every email the system sends. Stored in `app_settings` like the delivery settings; the logo
 * file lives in uploads/branding/ and `branding.logo` keeps its stored filename.
 */
function createBrandingService({ db, config }) {
  async function load() {
    const rows = await db.query(
      `SELECT s.\`key\` AS \`key\`, s.value, s.updated_at AS updatedAt
         FROM app_settings s WHERE s.\`key\` IN (?, ?, ?, ?, ?)`,
      [KEY_COMPANY, KEY_LOGO, KEY_TAGLINE, KEY_COLOR, KEY_KIT],
    );
    return Object.fromEntries(rows.map((r) => [r.key, r]));
  }

  async function view() {
    const rows = await load();
    const updated = Object.values(rows).reduce((a, r) => (!a || r.updatedAt > a ? r.updatedAt : a), null);
    const kit = parseKit(rows[KEY_KIT]?.value);
    const font = (name) => (BRAND_FONTS[name] ? name : DEFAULT_FONT);
    return {
      companyName: rows[KEY_COMPANY]?.value || config.appName,
      tagline: rows[KEY_TAGLINE]?.value || null,
      // "#RRGGBB", or null for the console's built-in accent.
      brandColor: rows[KEY_COLOR]?.value || null,
      hasLogo: Boolean(rows[KEY_LOGO]?.value),
      // Changes whenever the logo does, so clients can cache the image by it.
      logoVersion: rows[KEY_LOGO]?.value ?? null,
      headingFont: font(kit.headingFont),
      bodyFont: font(kit.bodyFont),
      letterhead: Object.fromEntries(LETTERHEAD_FIELDS.map((f) => [f, kit.letterhead?.[f] || null])),
      emailSignature: kit.emailSignature || null,
      fonts: Object.keys(BRAND_FONTS),
      updatedAt: updated,
    };
  }

  function put(key, value, userId, executor) {
    return db.exec(
      `INSERT INTO app_settings (\`key\`, value, is_secret, updated_by, updated_at) VALUES (?, ?, false, ?, ?)
       ON DUPLICATE KEY UPDATE value = VALUES(value), updated_by = VALUES(updated_by), updated_at = VALUES(updated_at)`,
      [key, value, userId, new Date()],
      executor,
    );
  }

  async function setCompanyName(name, userId) {
    await put(KEY_COMPANY, name.trim() || null, userId);
    return view();
  }

  /**
   * Any part of the branding — only the fields present in [dto] change (a letterhead field left
   * out keeps its value; null / '' clears it).
   */
  async function setIdentity(dto, userId) {
    if (dto.companyName !== undefined) await put(KEY_COMPANY, dto.companyName.trim() || null, userId);
    if (dto.tagline !== undefined) await put(KEY_TAGLINE, dto.tagline?.trim() || null, userId);
    if (dto.brandColor !== undefined) await put(KEY_COLOR, dto.brandColor ? dto.brandColor.toUpperCase() : null, userId);
    const kitFields = ['headingFont', 'bodyFont', 'letterhead', 'emailSignature'];
    if (kitFields.some((f) => dto[f] !== undefined)) {
      const kit = parseKit((await load())[KEY_KIT]?.value);
      if (dto.headingFont !== undefined) kit.headingFont = dto.headingFont || undefined;
      if (dto.bodyFont !== undefined) kit.bodyFont = dto.bodyFont || undefined;
      if (dto.emailSignature !== undefined) kit.emailSignature = dto.emailSignature?.trim() || undefined;
      if (dto.letterhead !== undefined) {
        const next = { ...kit.letterhead };
        for (const [f, v] of Object.entries(dto.letterhead ?? {})) next[f] = v?.trim() || undefined;
        kit.letterhead = next;
      }
      await put(KEY_KIT, JSON.stringify(kit), userId);
    }
    return view();
  }

  /** What every email is dressed in (core/email-template.js). */
  async function emailBrand() {
    const v = await view();
    return {
      appName: v.companyName,
      tagline: v.tagline,
      accent: v.brandColor,
      headingFont: BRAND_FONTS[v.headingFont],
      bodyFont: BRAND_FONTS[v.bodyFont],
      signature: v.emailSignature,
      contact: [v.letterhead.address, v.letterhead.phone, v.letterhead.email, v.letterhead.website].filter(Boolean),
      registration: v.letterhead.registration,
    };
  }

  async function setLogo(filename, userId) {
    const previous = (await load())[KEY_LOGO]?.value;
    await put(KEY_LOGO, filename, userId);
    if (previous && previous !== filename) deleteImageFile(BRANDING_UPLOAD_SUBDIR, previous);
    return view();
  }

  async function clearLogo(userId) {
    const previous = (await load())[KEY_LOGO]?.value;
    await put(KEY_LOGO, null, userId);
    if (previous) deleteImageFile(BRANDING_UPLOAD_SUBDIR, previous);
    return view();
  }

  async function logoFilename() {
    return (await load())[KEY_LOGO]?.value || null;
  }

  return { view, setCompanyName, setIdentity, emailBrand, setLogo, clearLogo, logoFilename };
}

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
  // The letterhead on PDF reports and the contact line under every email.
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

/**
 * Company branding (Settings → Branding). Reading it is PUBLIC — the sign-in page shows the name,
 * logo and colours before anyone is signed in, and none of it is secret — while changing it needs
 * `settings.manage`.
 */
function brandingRoutes(app) {
  const { branding } = app.services;
  const manage = [app.authenticate, app.requirePermissions('settings.manage')];

  app.get('/', async () => branding.view());

  app.put('/', { onRequest: manage, schema: { body: { ...obj(identityBody), minProperties: 1 } } }, async (request) => {
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'branding';
    request.auditOldValue = await branding.view();
    return branding.setIdentity(request.body, request.user.id);
  });

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

module.exports = { createBrandingService, brandingRoutes, BRANDING_UPLOAD_SUBDIR, BRAND_FONTS };
