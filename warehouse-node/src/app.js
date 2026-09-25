'use strict';

const Fastify = require('fastify');
const { loadConfig } = require('./config');
const { createPrisma } = require('./core/prisma');
const { createCache } = require('./core/cache/cache');
const { createAuth } = require('./core/auth');
const { AJV_OPTIONS, installErrorHandling } = require('./core/http');
const { installAudit } = require('./core/audit');
const { buildServices } = require('./container');

/** [mountPath, routes plugin]. Order does not matter: Fastify's router prefers static over parametric segments. */
const MODULES = [
  ['/auth', require('./modules/auth/routes')],
  ['/users/me/workstreams', require('./modules/workstream-managers/routes').myWorkstreamsRoutes],
  ['/users', require('./modules/users/routes')],
  ['/roles', require('./modules/roles/routes')],
  ['/permissions', require('./modules/permissions/routes')],
  ['/audit-logs', require('./modules/audit/routes')],
  ['/api-keys', require('./modules/api-keys/routes')],
  ['/warehouses', require('./modules/warehouses/routes')],
  ['/locations', require('./modules/locations/routes')],
  ['/workstreams/:workstreamId/managers', require('./modules/workstream-managers/routes').workstreamManagersRoutes],
  ['/workstreams', require('./modules/workstreams/routes')],
  ['/categories', require('./modules/categories/routes')],
  ['/attribute-types', require('./modules/attribute-types/routes')],
  ['/products/import', require('./modules/product-import/routes')],
  ['/products/:productId/images', require('./modules/product-images/routes')],
  ['/products', require('./modules/products/routes')],
  ['/inventory/receiving', require('./modules/receiving/routes')],
  ['/inventory/transfers', require('./modules/transfers/routes')],
  ['/inventory/adjustments', require('./modules/stock-adjustments/routes')],
  ['/inventory/counts', require('./modules/stock-counts/routes')],
  ['/inventory', require('./modules/inventory/routes')],
  ['/api/v1', require('./modules/external-api/routes')],
  ['/reports', require('./modules/reports/routes').reportsRoutes],
  ['/dashboard', require('./modules/reports/routes').dashboardRoutes],
];

/**
 * Builds the Fastify instance without listening — tests call this directly; server.js listens.
 * `overrides` lets a test inject its own config / prisma / cache.
 */
async function buildApp(overrides = {}) {
  const config = overrides.config ?? loadConfig();
  const prisma = overrides.prisma ?? createPrisma();
  const cache = overrides.cache ?? createCache(config.cache);

  const app = Fastify({
    logger: overrides.logger ?? { level: process.env.LOG_LEVEL ?? 'info' },
    trustProxy: config.trustProxy,
    ajv: AJV_OPTIONS,
    // Behind cPanel/Passenger the app sits behind a proxy; keep-alive matches Node's default LB idle timeout.
    keepAliveTimeout: 65_000,
    bodyLimit: 1024 * 1024,
  });

  const auth = createAuth({ config, prisma, cache });

  app.decorate('config', config);
  app.decorate('prisma', prisma);
  app.decorate('cache', cache);
  app.decorate('authenticate', auth.authenticate);
  app.decorate('requirePermissions', auth.requirePermissions);
  app.decorate('requireScopes', auth.requireScopes);
  app.decorate('services', buildServices({ prisma, cache, config, auth }));

  installErrorHandling(app, { logger: app.log });
  installAudit(app, { prisma, basePath: config.basePath });

  // Express tolerated an empty body on a JSON request (e.g. POST .../revoke); Fastify rejects it by default.
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (_request, body, done) => {
    if (!body) return done(null, {});
    try {
      done(null, JSON.parse(body));
    } catch (error) {
      error.statusCode = 400;
      done(error);
    }
  });

  // POST answers 201 unless a handler overrides it (Nest's default; login/refresh/logout etc. set 200).
  app.addHook('onRequest', async (request, reply) => {
    if (request.method === 'POST') reply.code(201);
  });

  await app.register(require('@fastify/helmet'));
  await app.register(require('@fastify/cors'), {
    origin: config.corsOrigins,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });
  await app.register(require('@fastify/compress'), { threshold: 1024 });
  await app.register(require('@fastify/etag'));
  await app.register(require('@fastify/multipart'), { limits: { files: 1, fields: 20 } });

  // Everything (including /health) mounts under API_BASE_PATH when the app is served from a sub-path.
  await app.register(
    async function api(scope) {
      scope.get('/health', async () => ({ status: 'ok' }));
      for (const [mountPath, plugin] of MODULES) {
        await scope.register(plugin, { prefix: mountPath });
      }
    },
    { prefix: config.basePath ? `/${config.basePath}` : '' },
  );

  app.addHook('onClose', async () => {
    await prisma.$disconnect();
  });

  return app;
}

module.exports = { buildApp };
