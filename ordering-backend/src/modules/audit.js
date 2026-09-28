'use strict';

const { obj, str, uuid, int, dateString } = require('../core/schema');
const { cols, nest, hydrate, Where } = require('../core/models');

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

/** Pure read of audit_logs — the rows the audit middleware writes on every mutation. */
function auditRoutes(app) {
  const { db } = app;

  app.get(
    '/',
    { onRequest: [app.authenticate, app.requirePermissions('audit.view')], schema: { querystring: query } },
    async (request) => {
      const q = request.query;
      const page = q.page ?? 1;
      const pageSize = q.pageSize ?? 20;
      const where = new Where().eq('a.user_id', q.userId).eq('a.entity', q.entity).eq('a.entity_id', q.entityId).eq('a.action', q.action);
      if (q.from) where.raw('a.created_at >= ?', new Date(q.from));
      if (q.to) where.raw('a.created_at <= ?', new Date(q.to));

      const [countRow, rows] = await Promise.all([
        db.one(`SELECT COUNT(*) AS total FROM audit_logs a ${where.sql}`, where.params),
        db.query(
          `SELECT ${cols('auditLog', 'a')}, ${cols('user', 'u', ['id', 'fullName', 'email'], 'user.')}
             FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id
             ${where.sql}
            ORDER BY a.created_at DESC
            LIMIT ? OFFSET ?`,
          [...where.params, pageSize, (page - 1) * pageSize],
        ),
      ]);
      const total = Number(countRow.total);
      return { data: hydrate('auditLog', rows.map(nest)), page, pageSize, total, totalPages: Math.ceil(total / pageSize) || 0 };
    },
  );
}

module.exports = { auditRoutes };
