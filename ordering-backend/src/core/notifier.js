'use strict';

const { renderEmail, renderText } = require('./email-template');

/**
 * Sends email and SMS, and records every attempt in the `notifications` table.
 *
 * Where messages go comes from `deliverySettings.effective()` — what an administrator saved in the
 * app (Settings → Email & SMS delivery), falling back to `.env`. It is read on every send, so a
 * change takes effect immediately. Transports (email.transport / sms.transport):
 *   smtp     email through any SMTP server (nodemailer)
 *   httpsms  SMS through httpsms.com (POST /v1/messages/send, x-api-key) — texts go out from the
 *            Android phone registered in the httpSMS app (sms.from)
 *   log      print the message to the server log instead of sending (the default until the real
 *            transport is configured, so everything works in development)
 *   memory   keep messages in `notifier.outbox` (test harness only)
 *
 * send() never throws for a delivery failure — it returns { ok, status, error } and the row says
 * FAILED — because a notification must never break the business action that triggered it. Callers
 * that NEED delivery (a one-time code) check `ok` and report the failure to the user themselves.
 */
function createNotifier({ config, models, logger, deliverySettings }) {
  const outbox = [];
  let smtp;
  let smtpKey;

  /** One SMTP connection pool per distinct setting set — rebuilt when an admin changes them. */
  function smtpTransport(email) {
    const key = JSON.stringify([email.host, email.port, email.secure, email.user, email.pass]);
    if (!smtp || smtpKey !== key) {
      const nodemailer = require('nodemailer');
      smtp?.close?.();
      smtp = nodemailer.createTransport({
        host: email.host,
        port: email.port,
        secure: email.secure,
        auth: email.user ? { user: email.user, pass: email.pass } : undefined,
      });
      smtpKey = key;
    }
    return smtp;
  }

  async function deliverEmail(email, to, subject, text, html) {
    switch (email.transport) {
      case 'smtp':
        await smtpTransport(email).sendMail({
          from: email.from.includes('<') ? email.from : { name: config.appName, address: email.from },
          to,
          subject,
          text,
          html,
        });
        return 'SENT';
      case 'memory':
        outbox.push({ channel: 'EMAIL', to, subject, text, html });
        return 'LOGGED';
      case 'log':
        logger.info(`[email -> ${to}] ${subject}\n${text}`);
        return 'LOGGED';
      default:
        throw new Error(`Unknown email transport "${email.transport}"`);
    }
  }

  async function deliverSms(sms, to, text) {
    switch (sms.transport) {
      case 'httpsms': {
        if (!sms.apiKey || !sms.from) throw new Error('The httpSMS API key and phone number must both be set');
        const res = await fetch(`${sms.baseUrl}/v1/messages/send`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-api-key': sms.apiKey },
          body: JSON.stringify({ from: sms.from, to, content: text }),
          signal: AbortSignal.timeout(15_000),
        });
        const reply = await res.text();
        if (!res.ok) throw new Error(`httpSMS responded ${res.status}: ${reply.slice(0, 300)}`);
        // httpSMS only QUEUES the text; the Android phone sends it later. Keep its message id and
        // queue status so a message stuck on the phone side can be traced (httpsms.com → Messages).
        let info = null;
        try {
          const { data } = JSON.parse(reply);
          if (data) info = `httpSMS message ${data.id} from ${data.owner ?? sms.from}: ${data.status}`;
        } catch {
          // Not JSON — nothing to record; the 2xx already means httpSMS accepted it.
        }
        return { status: 'SENT', info };
      }
      case 'memory':
        outbox.push({ channel: 'SMS', to, text });
        return 'LOGGED';
      case 'log':
        logger.info(`[sms -> ${to}] ${text}`);
        return 'LOGGED';
      default:
        throw new Error(`Unknown SMS transport "${sms.transport}"`);
    }
  }

  /**
   * message: { userId?, event, channel: 'EMAIL'|'SMS', to, subject?, text, email?, sensitive? }
   * `text` is the short form (SMS). `email` is the structured content of the branded HTML email
   * (core/email-template.js); an email without it falls back to a plain `text` email.
   * `sensitive` (one-time codes) keeps the text out of the notifications table.
   */
  async function send(message) {
    const { userId = null, event, channel, to, subject, sensitive = false } = message;
    let { text } = message;
    let status;
    let error = null;
    let providerInfo = null;
    try {
      const settings = await deliverySettings.effective();
      if (channel === 'SMS') {
        const result = await deliverSms(settings.sms, to, text);
        ({ status } = typeof result === 'string' ? { status: result } : result);
        providerInfo = result.info ?? null;
        if (providerInfo) logger.info(`Notification (${event}) to ${to}: ${providerInfo}`);
      } else {
        let html;
        if (message.email) {
          html = renderEmail(message.email, config);
          text = renderText(message.email, config);
        }
        status = await deliverEmail(settings.email, to, subject ?? config.appName, text, html);
      }
    } catch (err) {
      status = 'FAILED';
      error = err.message;
      logger.warn(`Notification (${event}) to ${to} via ${channel} failed: ${err.message}`);
    }

    await models
      .insert('notification', {
        userId,
        event,
        channel,
        destination: to,
        subject: channel === 'EMAIL' ? (subject ?? config.appName) : null,
        body: sensitive ? '[one-time code — not stored]' : text,
        status,
        error,
      })
      .catch((err) => logger.warn(`Could not record notification: ${err.message}`));

    return { ok: status !== 'FAILED', status, error, providerInfo };
  }

  return { send, outbox };
}

module.exports = { createNotifier };
