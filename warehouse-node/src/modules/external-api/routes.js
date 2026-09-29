'use strict';

const { ProductStatus } = require('../../core/enums');
const { obj, nonEmpty, str, num, uuid, opt, arrayOf, enumOf, boolQuery } = require('../../core/schema');

// System-to-system: authenticated by X-API-Key (never a user JWT), scoped per route, mounted at /api/v1.
// Business outcomes (shortfall, already released/issued) come back as HTTP 200 with a discriminator
// field, NOT as error status codes — consumers must check the discriminator, not just the status.

const catalogueQuery = obj({
  categoryId: uuid,
  workstreamId: uuid,
  status: enumOf(ProductStatus),
  includeInactive: boolQuery,
  search: str(),
  attribute: str(),
});

const quantity = num({ multipleOf: 0.001, exclusiveMinimum: 0 });
const stockLine = obj({ productId: uuid, locationId: uuid, quantity }, ['productId', 'locationId', 'quantity']);

const availabilityBody = obj(
  { items: arrayOf(obj({ productId: uuid, locationId: opt(uuid) }, ['productId']), { minItems: 1 }) },
  ['items'],
);
const issueBody = obj({ reference: nonEmpty(), lines: arrayOf(stockLine, { minItems: 1 }) }, ['reference', 'lines']);
// `label` is optional human text for the packing screen (e.g. "ORD-0012 · Customer name").
const reserveBody = obj(
  { reference: nonEmpty(), label: opt(str({ maxLength: 191 })), lines: arrayOf(stockLine, { minItems: 1 }) },
  ['reference', 'lines'],
);
const releaseBody = obj({ reference: nonEmpty() }, ['reference']);

function externalApiRoutes(app) {
  const { products, categories, warehouses, locations, stockReservations } = app.services;
  const { requireScopes } = app;

  // Read view over the same services the internal /products and /categories routes use; no new business logic.
  // findAll() is cached (catalogue + stock tags), so a polling consumer costs one DB read per TTL.
  app.get(
    '/catalogue',
    { onRequest: [requireScopes('catalogue:read')], schema: { querystring: catalogueQuery } },
    async (request) => {
      const query = request.query;
      const [productRows, categoryRows] = await Promise.all([
        products.findAll(query),
        // Workstream info rides along on every category (and, nested, on every product's category).
        categories.findAll({ workstreamId: query.workstreamId }),
      ]);
      return { categories: categoryRows, products: productRows };
    },
  );

  // Active locations only, flat (no ancestor chain) — a consumer resolves the path by walking parentId.
  app.get('/locations', { onRequest: [requireScopes('locations:read')] }, async () => {
    const [warehouseRows, locationRows] = await Promise.all([warehouses.findAll(), locations.findAll()]);
    return { warehouses: warehouseRows, locations: locationRows };
  });

  // Stock operations. Never cached: reserve/issue decisions must read the live ledger.
  app.post(
    '/stock/availability',
    { onRequest: [requireScopes('stock:read')], schema: { body: availabilityBody } },
    async (request, res) => {
      res.status(200);
      return stockReservations.checkAvailability(request.body);
    },
  );

  // Where each product can be reserved from (active locations with available stock + stock age), so the
  // ordering system can propose FIFO allocations. Read-only, same scope as availability.
  app.post(
    '/stock/allocation-options',
    {
      onRequest: [requireScopes('stock:read')],
      schema: { body: obj({ productIds: arrayOf(uuid, { minItems: 1, maxItems: 500 }) }, ['productIds']) },
    },
    async (request, res) => {
      res.status(200);
      return stockReservations.allocationOptions(request.body);
    },
  );

  const stockAction = (path, scope, verb, bodySchema, run) => {
    app.post(
      `/stock/${path}`,
      { onRequest: [requireScopes(scope)], schema: { body: bodySchema } },
      async (request, res) => {
        request.auditEntity = 'stock_reservations';
        request.auditEntityId = request.body.reference;
        request.auditAction = verb;
        res.status(200);
        return run(request);
      },
    );
  };

  stockAction('reserve', 'stock:reserve', 'RESERVE', reserveBody, (request) =>
    stockReservations.reserve(request.body, request.apiKey.id),
  );
  stockAction('release', 'stock:reserve', 'RELEASE', releaseBody, (request) =>
    stockReservations.release(request.body),
  );
  stockAction('issue', 'stock:issue', 'ISSUE', issueBody, (request) => stockReservations.issue(request.body));
}

module.exports = externalApiRoutes;
