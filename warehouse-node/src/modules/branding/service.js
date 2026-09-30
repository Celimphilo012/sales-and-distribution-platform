'use strict';

const { deleteImageFile } = require('../../core/uploads');
const { BRAND_FONTS, DEFAULT_FONT } = require('./fonts');

const BRANDING_UPLOAD_SUBDIR = 'branding';
const KEY_COMPANY = 'branding.company';
const KEY_LOGO = 'branding.logo';
const KEY_TAGLINE = 'branding.tagline';
const KEY_COLOR = 'branding.color';
// The brand kit — fonts, letterhead and email signature — as one JSON document, so new kit
// fields can be added without a new settings key each.
const KEY_KIT = 'branding.kit';

const LETTERHEAD_FIELDS = ['address', 'phone', 'email', 'website', 'registration', 'footer'];

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
 * and the email signature. Used for the console's look, every PDF / Excel export, pick list and
 * label, and every email the system sends. Stored in `app_settings` like the delivery settings;
 * the logo file lives in uploads/branding/ and `branding.logo` keeps its stored filename.
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

module.exports = { createBrandingService, BRANDING_UPLOAD_SUBDIR };
