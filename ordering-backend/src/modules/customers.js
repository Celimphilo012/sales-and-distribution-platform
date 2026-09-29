'use strict';

const { cols, Where } = require('../core/models');
const { CustomerStatus } = require('../core/enums');
const { obj, str, opt, enumOf, boolQuery, uuidParams } = require('../core/schema');

const containsPattern = (text) => `%${text.replace(/[\\%_]/g, '\\$&')}%`;
const CUSTOMER_FIELDS = ['name', 'phone', 'address', 'locationText', 'notes'];

function createCustomersService({ db, models }) {
  function findAll(query = {}) {
    const where = new Where();
    if (!query.includeInactive) where.raw("c.status = 'ACTIVE'");
    // The *_ci collation already makes LIKE case-insensitive.
    if (query.search) where.raw('(c.name LIKE ? OR c.phone LIKE ?)', containsPattern(query.search), containsPattern(query.search));
    return db.query(`SELECT ${cols('customer', 'c')} FROM customers c ${where.sql} ORDER BY c.name ASC`, where.params);
  }

  const getExisting = (id) => models.getById('customer', id, 'Customer');

  const pick = (dto, fields) => Object.fromEntries(fields.map((f) => [f, dto[f]]));

  const create = (dto) => models.insert('customer', pick(dto, CUSTOMER_FIELDS));

  async function update(id, dto) {
    await getExisting(id);
    const data = pick(dto, [...CUSTOMER_FIELDS, 'status']);
    if (data.name === null) data.name = undefined; // required column
    if (data.status === null) data.status = undefined;
    return models.update('customer', id, data, 'Customer');
  }

  async function remove(id) {
    await getExisting(id);
    // Reference data is soft-deleted (rule 10) — orders keep a valid historical customer.
    return models.update('customer', id, { status: 'INACTIVE' }, 'Customer');
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove };
}

const optional = { phone: opt(str()), address: opt(str()), locationText: opt(str()), notes: opt(str()) };

function customersRoutes(app) {
  const { customers } = app.services;
  const view = [app.authenticate, app.requirePermissions('customers.view')];
  // Every write is gated customers.create (there is no separate edit/delete key).
  const write = [app.authenticate, app.requirePermissions('customers.create')];
  const idParams = { params: uuidParams('id') };
  const confirmDeactivate = app.services.otp.requireOtp('customer.deactivate', {
    when: (req) => req.method === 'DELETE' || (req.body.status != null && req.body.status !== 'ACTIVE'),
  });

  app.get(
    '/',
    { onRequest: view, schema: { querystring: obj({ includeInactive: boolQuery, search: str() }) } },
    async (request) => customers.findAll(request.query),
  );
  app.get('/:id', { onRequest: view, schema: idParams }, async (request) => customers.findOne(request.params.id));
  app.post(
    '/',
    { onRequest: write, schema: { body: obj({ name: str({ minLength: 1 }), ...optional }, ['name']) } },
    async (request) => customers.create(request.body),
  );
  app.patch(
    '/:id',
    {
      onRequest: write,
      preHandler: [confirmDeactivate],
      schema: { ...idParams, body: obj({ name: opt(str({ minLength: 1 })), ...optional, status: opt(enumOf(CustomerStatus)) }) },
    },
    async (request) => {
      request.auditOldValue = await customers.getExisting(request.params.id);
      return customers.update(request.params.id, request.body);
    },
  );
  app.delete('/:id', { onRequest: write, preHandler: [confirmDeactivate], schema: idParams }, async (request) => {
    request.auditOldValue = await customers.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return customers.remove(request.params.id);
  });
}

module.exports = { createCustomersService, customersRoutes };
