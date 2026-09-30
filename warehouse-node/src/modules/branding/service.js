'use strict';

const { deleteImageFile } = require('../../core/uploads');

const BRANDING_UPLOAD_SUBDIR = 'branding';
const KEY_COMPANY = 'branding.company';
const KEY_LOGO = 'branding.logo';

/**
 * Report branding: the company name and logo printed at the top of every PDF / Excel export and
 * pick list (Settings → Report branding). Stored in `app_settings` like the delivery settings; the
 * logo file lives in uploads/branding/ and `branding.logo` keeps its stored filename.
 */
function createBrandingService({ db, config }) {
  async function load() {
    const rows = await db.query(
      `SELECT s.\`key\` AS \`key\`, s.value, s.updated_at AS updatedAt
         FROM app_settings s WHERE s.\`key\` IN (?, ?)`,
      [KEY_COMPANY, KEY_LOGO],
    );
    return Object.fromEntries(rows.map((r) => [r.key, r]));
  }

  async function view() {
    const rows = await load();
    const updated = Object.values(rows).reduce((a, r) => (!a || r.updatedAt > a ? r.updatedAt : a), null);
    return {
      companyName: rows[KEY_COMPANY]?.value || config.appName,
      hasLogo: Boolean(rows[KEY_LOGO]?.value),
      // Changes whenever the logo does, so clients can cache the image by it.
      logoVersion: rows[KEY_LOGO]?.value ?? null,
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

  return { view, setCompanyName, setLogo, clearLogo, logoFilename };
}

module.exports = { createBrandingService, BRANDING_UPLOAD_SUBDIR };
