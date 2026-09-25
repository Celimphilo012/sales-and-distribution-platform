'use strict';

const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const METHOD_ACTIONS = { POST: 'CREATE', PUT: 'UPDATE', PATCH: 'UPDATE', DELETE: 'DELETE' };
const SENSITIVE_KEYS = new Set([
  'password',
  'passwordHash',
  'currentPassword',
  'newPassword',
  'refreshToken',
  'accessToken',
  'token',
]);

function redact(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return undefined;
  const out = {};
  for (const [key, value] of Object.entries(body)) out[key] = SENSITIVE_KEYS.has(key) ? '[REDACTED]' : value;
  return out;
}

/**
 * Writes one audit_logs row for every mutating request that completes
 * successfully (status < 400). Entity defaults to the first URL segment and the
 * entity id to the most specific route param, exactly like the original
 * AuditInterceptor. Handlers may set request.auditEntity / auditEntityId /
 * auditOldValue / auditAction / auditBody to override any of these.
 *
 * The write happens in onResponse — after the client already has its answer —
 * so auditing adds no latency, and a failed audit write never breaks a request.
 */
function installAudit(app, { prisma, basePath }) {
  app.decorateRequest('user', null);
  app.decorateRequest('apiKey', null);
  app.decorateRequest('auditEntity', null);
  app.decorateRequest('auditEntityId', null);
  app.decorateRequest('auditOldValue', null);
  app.decorateRequest('auditAction', null);
  app.decorateRequest('auditBody', null);
  app.decorateRequest('responseId', null);

  const prefix = basePath ? `/${basePath}` : '';

  app.addHook('preSerialization', async (request, _reply, payload) => {
    if (MUTATING_METHODS.has(request.method) && payload && typeof payload === 'object') {
      request.responseId = payload.id ?? null;
    }
    return payload;
  });

  app.addHook('onResponse', async (request, reply) => {
    const method = request.method;
    if (!MUTATING_METHODS.has(method) || reply.statusCode >= 400) return;

    try {
      let path = request.url.split('?')[0];
      if (prefix && path.startsWith(prefix)) path = path.slice(prefix.length);

      const entity = request.auditEntity ?? path.split('/').filter(Boolean)[0] ?? 'unknown';
      const params = Object.values(request.params ?? {});
      const entityId = request.auditEntityId ?? params[params.length - 1] ?? request.responseId ?? null;
      const body = request.auditBody ?? request.body;

      await prisma.auditLog.create({
        data: {
          userId: request.user?.id ?? null,
          // External-API calls authenticate with an API key, never a user: record which key acted.
          apiKeyId: request.apiKey?.id ?? null,
          action: request.auditAction ?? METHOD_ACTIONS[method] ?? method,
          entity,
          entityId: entityId ?? null,
          oldValue: request.auditOldValue ?? undefined,
          newValue: method === 'DELETE' ? undefined : redact(body),
        },
      });
    } catch {
      // Audit logging must never break the request/response cycle.
    }
  });
}

module.exports = { installAudit };
