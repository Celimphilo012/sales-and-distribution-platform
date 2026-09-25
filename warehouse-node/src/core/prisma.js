'use strict';

const { PrismaClient } = require('@prisma/client');

/**
 * One PrismaClient per process. Pool size is controlled through the
 * DATABASE_URL query string (e.g. `?connection_limit=10&pool_timeout=20`);
 * on shared hosting keep it small — every extra connection is memory and a
 * slot against the host's max_user_connections.
 */
function createPrisma() {
  return new PrismaClient();
}

module.exports = { createPrisma };
