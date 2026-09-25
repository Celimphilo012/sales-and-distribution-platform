'use strict';

const { obj, str, uuid, int, dateString } = require('../../core/schema');

const query = obj({
  userId: uuid,
  entity: str(),
  entityId: str(),
  action: str(),
  from: dateString,
  to: dateString,
  page: int({ minimum: 1 }),
  pageSize: int({ minimum: 1, maximum: 100 }),
});

/** Pure read of audit_logs — the rows the audit hook already writes on every mutation. Never cached: it must show the latest write. */
async function auditRoutes(app) {
  const { prisma } = app;

  app.get(
    '/',
    { onRequest: [app.authenticate, app.requirePermissions('audit.view')], schema: { querystring: query } },
    async (request) => {
      const q = request.query;
      const page = q.page ?? 1;
      const pageSize = q.pageSize ?? 20;

      const where = {
        userId: q.userId,
        entity: q.entity,
        entityId: q.entityId,
        action: q.action,
        createdAt: {
          gte: q.from ? new Date(q.from) : undefined,
          lte: q.to ? new Date(q.to) : undefined,
        },
      };

      const [total, data] = await Promise.all([
        prisma.auditLog.count({ where }),
        prisma.auditLog.findMany({
          where,
          include: {
            user: { select: { id: true, fullName: true, email: true } },
            // A row is attributed to a user OR an API key, never both.
            apiKey: { select: { id: true, name: true } },
          },
          orderBy: { createdAt: 'desc' },
          skip: (page - 1) * pageSize,
          take: pageSize,
        }),
      ]);

      return { data, page, pageSize, total, totalPages: Math.ceil(total / pageSize) || 0 };
    },
  );
}

module.exports = auditRoutes;
