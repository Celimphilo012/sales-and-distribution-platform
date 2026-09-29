'use strict';

const { badRequest } = require('../core/errors');
const { deriveKey, encrypt, decrypt } = require('../core/crypto');
const { obj, str, int, bool, opt } = require('../core/schema');

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

function createDeliverySettingsService({ db, config }) {
  const key = deriveKey(config.secretsKey);

  async function loadRows() {
    return db.query(
      `SELECT s.\`key\` AS \`key\`, s.value, s.is_secret AS isSecret, s.updated_at AS updatedAt,
              u.full_name AS updatedByName
         FROM app_settings s LEFT JOIN users u ON u.id = s.updated_by
        WHERE s.\`key\` LIKE 'email.%' OR s.\`key\` LIKE 'sms.%'`,
    );
  }

  // This process's copy of the effective settings; a save clears it (one process per app).
  let memo = null;
  const MEMO_TTL_MS = 60_000;

  /**
   * The settings the notifier actually uses: `.env` values overlaid with whatever an admin saved.
   * Read at most once a minute; any save clears it. The in-memory transport (test harness only) is
   * never replaced.
   */
  async function effective() {
    if (memo && memo.until > Date.now()) return memo.value;
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
    memo = { value: result, until: Date.now() + MEMO_TTL_MS };
    return result;
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
    memo = null;
    return view();
  }

  return { effective, view, update };
}

const deliveryBody = obj({
  email: opt(
    obj({
      transport: opt({ type: 'string', enum: ['smtp', 'log'] }),
      host: opt(str({ maxLength: 191 })),
      port: opt(int({ minimum: 1, maximum: 65535 })),
      secure: opt(bool),
      user: opt(str({ maxLength: 191 })),
      pass: opt(str({ maxLength: 500 })),
      from: opt(str({ maxLength: 191 })),
    }),
  ),
  sms: opt(
    obj({
      transport: opt({ type: 'string', enum: ['httpsms', 'log'] }),
      apiKey: opt(str({ maxLength: 500 })),
      from: opt(str({ maxLength: 32 })),
    }),
  ),
});

const testBody = obj({ channel: { type: 'string', enum: ['EMAIL', 'SMS'] }, to: str({ minLength: 3, maxLength: 191 }) }, [
  'channel',
  'to',
]);

/** Admin-editable email (SMTP) and SMS (httpSMS) delivery — gated `settings.manage`. */
function deliverySettingsRoutes(app) {
  const { deliverySettings, notifier } = app.services;
  const guard = [app.authenticate, app.requirePermissions('settings.manage')];

  app.get('/', { onRequest: guard }, async () => deliverySettings.view());

  app.put('/', { onRequest: guard, schema: { body: deliveryBody } }, async (request) => {
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'delivery';
    request.auditOldValue = await deliverySettings.view(); // secrets already reduced to has*
    // The audit trail records what changed, never the secrets themselves.
    const body = request.body;
    request.auditBody = {
      email: body.email && { ...body.email, ...(body.email.pass ? { pass: '[REDACTED]' } : {}) },
      sms: body.sms && { ...body.sms, ...(body.sms.apiKey ? { apiKey: '[REDACTED]' } : {}) },
    };
    return deliverySettings.update(body, request.user.id);
  });

  // Sends a real test message with the saved settings, so an admin knows they work.
  app.post('/test', { onRequest: guard, schema: { body: testBody } }, async (request, res) => {
    const { channel, to } = request.body;
    const result = await notifier.send({
      userId: request.user.id,
      event: 'delivery.test',
      channel,
      to,
      subject: `${app.config.appName}: test email`,
      text: `This is a test ${channel === 'SMS' ? 'SMS' : 'email'} from ${app.config.appName}. If you received it, delivery is set up correctly.`,
      email: {
        preheader: 'Email delivery is working',
        eyebrow: 'Delivery test',
        tone: 'success',
        heading: 'Email delivery is working',
        paragraphs: [
          `This test was sent from ${app.config.appName} with the email settings saved under Settings, Email & SMS delivery.`,
          'Sign-in codes, confirmation codes and order notifications will arrive looking like this.',
        ],
        details: [
          ['Sent by', request.user.fullName ?? request.user.email],
          ['Sent at', new Date().toUTCString().replace('GMT', 'UTC')],
        ],
      },
    });
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'delivery';
    request.auditAction = 'DELIVERY_TEST';
    res.status(200);
    return result;
  });
}

module.exports = { createDeliverySettingsService, deliverySettingsRoutes };
