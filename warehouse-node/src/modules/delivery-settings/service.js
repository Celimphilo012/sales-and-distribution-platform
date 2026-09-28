'use strict';

const { badRequest } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { deriveKey, encrypt, decrypt } = require('../../core/crypto');

/**
 * Email (SMTP) and SMS (httpSMS) delivery settings, editable by an administrator in the app
 * (Settings → Email & SMS delivery) and stored in `app_settings`. Anything saved here overrides the
 * `.env` values, which remain only as the fallback (e.g. a first deployment).
 *
 * The SMTP password and the httpSMS API key are secrets: encrypted at rest with
 * SECRETS_ENCRYPTION_KEY, never returned by the API (only whether one is set), and a blank value on
 * save means "keep what is stored".
 */
const FIELDS = {
  'email.transport': { type: 'enum', values: ['smtp', 'log'] },
  'email.host': { type: 'string' },
  'email.port': { type: 'int' },
  'email.secure': { type: 'bool' },
  'email.user': { type: 'string' },
  'email.pass': { type: 'string', secret: true },
  'email.from': { type: 'string' },
  'sms.transport': { type: 'enum', values: ['httpsms', 'log'] },
  'sms.apiKey': { type: 'string', secret: true },
  'sms.from': { type: 'string' },
};

const parse = (type, raw) => {
  if (raw === null || raw === undefined) return null;
  if (type === 'int') return Number(raw);
  if (type === 'bool') return raw === 'true';
  return raw;
};

function createDeliverySettingsService({ db, cache, config }) {
  const key = deriveKey(config.secretsKey);

  async function loadRows() {
    return db.query(
      `SELECT s.\`key\` AS \`key\`, s.value, s.is_secret AS isSecret, s.updated_at AS updatedAt,
              u.full_name AS updatedByName
         FROM app_settings s LEFT JOIN users u ON u.id = s.updated_by
        WHERE s.\`key\` LIKE 'email.%' OR s.\`key\` LIKE 'sms.%'`,
    );
  }

  /**
   * The settings the notifier actually uses: `.env` values overlaid with whatever an admin saved.
   * Cached; any save invalidates it. The in-memory transport (test harness only) is never replaced.
   */
  function effective() {
    return cache.wrap('delivery-settings', { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.SETTINGS] }, async () => {
      const result = { email: { ...config.email }, sms: { ...config.sms } };
      for (const row of await loadRows()) {
        const def = FIELDS[row.key];
        if (!def) continue;
        const [section, field] = row.key.split('.');
        let value = row.value;
        if (row.isSecret && value) {
          try {
            value = decrypt(key, value);
          } catch {
            value = null; // encrypted with a different SECRETS_ENCRYPTION_KEY — treat as unset
          }
        }
        if (field === 'transport' && result[section].transport === 'memory') continue;
        result[section][field] = parse(def.type, value);
      }
      return result;
    });
  }

  /** What the admin screen shows: current values, with secrets reduced to "is one set?". */
  async function view() {
    const [settings, rows] = await Promise.all([effective(), loadRows()]);
    const latest = rows.reduce((a, r) => (!a || r.updatedAt > a.updatedAt ? r : a), null);
    const { pass, ...email } = settings.email;
    const { apiKey, baseUrl, ...sms } = settings.sms;
    return {
      email: { ...email, hasPassword: Boolean(pass) },
      sms: { ...sms, hasApiKey: Boolean(apiKey) },
      savedInApp: rows.length > 0,
      updatedAt: latest?.updatedAt ?? null,
      updatedByName: latest?.updatedByName ?? null,
    };
  }

  /**
   * Saves the given fields. `undefined` = leave as is. For the two secrets, `''` also means "keep"
   * (the form never receives them back); `null` clears them.
   */
  async function update(dto, userId) {
    const writes = [];
    for (const [section, values] of Object.entries(dto)) {
      for (const [field, value] of Object.entries(values ?? {})) {
        const name = `${section}.${field}`;
        const def = FIELDS[name];
        if (!def || value === undefined) continue;
        if (def.secret && value === '') continue;
        const text = value === null ? null : String(value).trim();
        writes.push({ name, value: def.secret && text ? encrypt(key, text) : text, secret: Boolean(def.secret) });
      }
    }

    // Check the RESULT is usable before saving it: sending on, but nowhere to send from, is an error.
    const current = await effective();
    const next = { email: { ...current.email }, sms: { ...current.sms } };
    for (const [section, values] of Object.entries(dto)) {
      for (const [field, value] of Object.entries(values ?? {})) {
        if (value === undefined || (FIELDS[`${section}.${field}`]?.secret && value === '')) continue;
        next[section][field] = value;
      }
    }
    if (next.email.transport === 'smtp' && (!next.email.host || !next.email.from)) {
      throw badRequest('To send real emails, fill in the SMTP host and the "from" address');
    }
    if (next.sms.transport === 'httpsms') {
      if (!next.sms.apiKey) throw badRequest('To send real SMS, enter the httpSMS API key');
      if (!/^\+[1-9]\d{6,14}$/.test(String(next.sms.from ?? '').replace(/[\s().-]/g, ''))) {
        throw badRequest('To send real SMS, enter the httpSMS phone number in international format, e.g. +26876000000');
      }
    }

    await db.transaction(async (tx) => {
      for (const w of writes) {
        await db.exec(
          `INSERT INTO app_settings (\`key\`, value, is_secret, updated_by, updated_at) VALUES (?, ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE value = VALUES(value), is_secret = VALUES(is_secret),
                                   updated_by = VALUES(updated_by), updated_at = VALUES(updated_at)`,
          [w.name, w.name === 'sms.from' && w.value ? w.value.replace(/[\s().-]/g, '') : w.value, w.secret, userId, new Date()],
          tx,
        );
      }
    });
    await cache.invalidate(TAGS.SETTINGS);
    return view();
  }

  return { effective, view, update };
}

module.exports = { createDeliverySettingsService };
