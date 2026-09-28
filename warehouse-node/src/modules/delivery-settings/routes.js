'use strict';

const { obj, str, int, bool, opt } = require('../../core/schema');

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
    });
    request.auditEntity = 'app_settings';
    request.auditEntityId = 'delivery';
    request.auditAction = 'DELIVERY_TEST';
    res.status(200);
    return result;
  });
}

module.exports = deliverySettingsRoutes;
