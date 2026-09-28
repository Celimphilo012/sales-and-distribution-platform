'use strict';

const { TAGS } = require('../../core/cache/cache');
const { cols } = require('../../core/models');

/** The permission catalog only changes when the seed script runs, so it is safe to cache for a while. */
function permissionsRoutes(app) {
  const { db, cache, config } = app;

  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('roles.manage')] }, async () =>
    cache.wrap('permissions:list', { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.PERMISSIONS] }, () =>
      db.query(`SELECT ${cols('permission', 'p')} FROM permissions p ORDER BY p.module ASC, p.key ASC`),
    ),
  );
}

module.exports = permissionsRoutes;
