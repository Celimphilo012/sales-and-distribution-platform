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
 * Express middleware that writes one audit_logs row for every mutating request that completes
 * successfully (status < 400) — rule 8. Entity defaults to the first URL segment and the entity id
 * to the most specific route param. Handlers may set req.auditEntity / auditEntityId /
 * auditOldValue / auditAction / auditBody to override any of these.
 *
 * Written on the response's 'finish' event — after the client has its answer — so auditing adds no
 * latency, and a failed audit write never breaks a request.
 */
function auditMiddleware({ models, basePath }) {
  const prefix = basePath ? `/${basePath}` : '';

  return function audit(req, res, next) {
    if (!MUTATING_METHODS.has(req.method)) return next();

    res.on('finish', () => {
      if (res.statusCode >= 400) return;

      let path = req.originalUrl.split('?')[0];
      if (prefix && path.startsWith(prefix)) path = path.slice(prefix.length);

      const entity = req.auditEntity ?? path.split('/').filter(Boolean)[0] ?? 'unknown';
      const params = Object.values(req.auditParams ?? {});
      const entityId = req.auditEntityId ?? params[params.length - 1] ?? req.responseId ?? null;
      const body = req.auditBody ?? req.body;

      models
        .insert('auditLog', {
          userId: req.user?.id ?? null,
          action: req.auditAction ?? METHOD_ACTIONS[req.method] ?? req.method,
          entity,
          entityId: entityId ?? null,
          oldValue: req.auditOldValue ?? undefined,
          newValue: req.method === 'DELETE' ? undefined : redact(body),
        })
        .catch(() => {
          // Audit logging must never break the request/response cycle.
        });
    });

    next();
  };
}

module.exports = { auditMiddleware, redact };
