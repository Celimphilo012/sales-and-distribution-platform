'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const { loadConfig } = require('./config');
const { createDb } = require('./core/db');
const { createModels } = require('./core/models');
const { createAuth } = require('./core/auth');
const { createRoutes, createErrorHandler, notFoundHandler } = require('./core/http');
const { auditMiddleware } = require('./core/audit');
const { createLogger, requestLogger } = require('./core/logger');
const { createWarehouseApi } = require('./core/warehouse-api');
const { createAuthService, authRoutes } = require('./modules/auth');
const { createUsersService, usersRoutes } = require('./modules/users');
const { createRolesService, rolesRoutes, permissionsRoutes } = require('./modules/roles');
const { auditRoutes } = require('./modules/audit');
const { createCustomersService, customersRoutes } = require('./modules/customers');
const { createOrdersService, ordersRoutes, catalogueRoutes, warehouseLocationsRoutes } = require('./modules/orders');
const { createReportsService, reportsRoutes, dashboardRoutes } = require('./modules/reports');

/** [mountPath, routes function]. Express matches in order: more specific mounts first. */
const MODULES = [
  ['/auth', authRoutes],
  ['/users', usersRoutes],
  ['/roles', rolesRoutes],
  ['/permissions', permissionsRoutes],
  ['/audit-logs', auditRoutes],
  ['/customers', customersRoutes],
  ['/orders', ordersRoutes],
  ['/catalogue', catalogueRoutes],
  ['/warehouse-locations', warehouseLocationsRoutes],
  ['/reports', reportsRoutes],
  ['/dashboard', dashboardRoutes],
];

/** Builds every service once, in dependency order (rule 9: cross-module calls go through services). */
function buildServices({ db, models, config, auth }) {
  const base = { db, models, config, auth };
  const services = {};
  services.warehouseApi = createWarehouseApi(base);
  services.auth = createAuthService(base);
  services.users = createUsersService(base);
  services.roles = createRolesService(base);
  services.customers = createCustomersService(base);
  services.orders = createOrdersService({ ...base, customers: services.customers, warehouseApi: services.warehouseApi });
  services.reports = createReportsService(base);
  return services;
}

/**
 * Builds the Express app without listening — tests and server.js both call this. The app carries
 * its context on app.locals, and app.close() releases the database pool.
 */
function buildApp(overrides = {}) {
  const config = overrides.config ?? loadConfig();
  const logger = overrides.logger ?? createLogger();
  const db = overrides.db ?? createDb(config.databaseUrl);
  const models = createModels(db);
  const auth = createAuth({ config, db });
  const services = buildServices({ db, models, config, auth });

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);
  app.set('etag', 'weak');

  app.use(requestLogger(logger));
  app.use(helmet());
  app.use(
    cors({
      origin: config.corsOrigins,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Authorization', 'Content-Type'],
    }),
  );
  app.use(compression({ threshold: 1024 }));
  app.use(express.json({ limit: '1mb' }));
  app.use(auditMiddleware({ models, basePath: config.basePath }));

  const router = express.Router();
  const routes = createRoutes(router);
  const shared = {
    config,
    db,
    models,
    services,
    authenticate: auth.authenticate,
    requirePermissions: auth.requirePermissions,
  };
  routes.scope('').get('/health', async () => ({ status: 'ok' }));
  for (const [mountPath, register] of MODULES) register({ ...shared, ...routes.scope(mountPath) });

  app.use(config.basePath ? `/${config.basePath}` : '/', router);
  app.use(notFoundHandler);
  app.use(createErrorHandler(logger));

  Object.assign(app.locals, { config, db, models, services, logger });
  app.close = () => db.close();
  return app;
}

module.exports = { buildApp };
