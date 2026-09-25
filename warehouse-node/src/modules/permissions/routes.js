'use strict';

const { TAGS } = require('../../core/cache/cache');

/** The permission catalog only changes when the seed script runs, so it is safe to cache for a while. */
async function permissionsRoutes(app) {
  const { prisma, cache, config } = app;

  app.get('/', { onRequest: [app.authenticate, app.requirePermissions('roles.manage')] }, async () =>
    cache.wrap('permissions:list', { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.PERMISSIONS] }, () =>
      prisma.permission.findMany({ orderBy: [{ module: 'asc' }, { key: 'asc' }] }),
    ),
  );
}

module.exports = permissionsRoutes;
