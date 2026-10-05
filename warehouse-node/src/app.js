'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const { loadConfig } = require('./config');
const { createDb } = require('./core/db');
const { createModels } = require('./core/models');
const { createCache } = require('./core/cache/cache');
const { createAuth } = require('./core/auth');
const { createRoutes, createErrorHandler, notFoundHandler } = require('./core/http');
const { auditMiddleware } = require('./core/audit');
const { createLogger, requestLogger } = require('./core/logger');
const { createNotifier } = require('./core/notifier');
const { createDeliverySettingsService } = require('./modules/delivery-settings/service');
const { createBrandingService } = require('./modules/branding/service');
const { buildServices } = require('./container');

/**
 * [mountPath, routes function]. ORDER MATTERS in Express (first match wins): more specific mounts
 * (/users/me/workstreams, /products/import, /inventory/receiving) come before their broader parent.
 */
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
  ['/sales', require('./modules/sales/routes')],
  ['/internal', require('./modules/sales/tick-route')],
  ['/api/v1', require('./modules/external-api/routes')],
  ['/packing', require('./modules/packing/routes')],
  ['/settings/delivery', require('./modules/delivery-settings/routes')],
  ['/settings/branding', require('./modules/branding/routes')],
  ['/reports', require('./modules/reports/routes').reportsRoutes],
  ['/dashboard', require('./modules/reports/routes').dashboardRoutes],
];

/**
 * Builds the Express app without listening — tests and server.js both call this.
 * `overrides` lets a test inject its own config / db / cache / logger.
 *
 * Returns the Express `app` (a plain (req, res) handler, so http.createServer(app) serves it) with
 * the shared context attached: app.locals.{config, db, cache, services}, and app.close() to release
 * the database pool.
 */
function buildApp(overrides = {}) {
  const config = overrides.config ?? loadConfig();
  const logger = overrides.logger ?? createLogger();
  const db = overrides.db ?? createDb(config.databaseUrl);
  const models = createModels(db);
  const cache = overrides.cache ?? createCache(config.cache);
  const auth = createAuth({ config, db, cache });
  // Delivery settings come first: the notifier reads them on every send.
  const deliverySettings = createDeliverySettingsService({ db, cache, config });
  // Branding too: every email is dressed in the company's name, colour, fonts and signature.
  const branding = createBrandingService({ db, config });
  const notifier = overrides.notifier ?? createNotifier({ config, models, logger, deliverySettings, branding });
  const services = buildServices({ db, models, cache, config, auth, notifier, logger, branding });
  Object.assign(services, { deliverySettings, notifier });

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);
  app.set('etag', 'weak'); // JSON responses carry an ETag; a matching If-None-Match gets a 304

  app.use(requestLogger(logger));
  app.use(helmet());
  app.use(
    cors({
      origin: config.corsOrigins,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      // X-OTP-*: the one-time code that confirms a sensitive action (modules/otp).
      allowedHeaders: ['Authorization', 'Content-Type', 'X-OTP-Challenge', 'X-OTP-Code'],
    }),
  );
  app.use(compression({ threshold: 1024 }));
  // Tolerates an empty body on a JSON request (e.g. POST .../revoke): req.body stays undefined.
  app.use(express.json({ limit: '1mb' }));
  app.use(auditMiddleware({ models, basePath: config.basePath }));

  // Everything (including /health) mounts under API_BASE_PATH when the app is served from a sub-path.
  const router = express.Router();
  const routes = createRoutes(router);
  const shared = {
    config,
    db,
    models,
    cache,
    services,
    authenticate: auth.authenticate,
    requirePermissions: auth.requirePermissions,
    requireScopes: auth.requireScopes,
  };

  routes.scope('').get('/health', async () => ({ status: 'ok' }));
  for (const [mountPath, register] of MODULES) register({ ...shared, ...routes.scope(mountPath) });

  app.use(config.basePath ? `/${config.basePath}` : '/', router);
  app.use(notFoundHandler);
  app.use(createErrorHandler(logger));

  Object.assign(app.locals, { config, db, models, cache, services, logger, notifier });
  app.close = () => db.close();
  return app;
}

module.exports = { buildApp };
