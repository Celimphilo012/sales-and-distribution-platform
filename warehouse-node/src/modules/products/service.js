'use strict';

const { ProductStatus } = require('@prisma/client');
const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const PRODUCT_INCLUDE = {
  category: {
    select: {
      id: true,
      name: true,
      workstreamId: true,
      workstream: { select: { id: true, name: true, code: true } },
      // One level up only — the frontend's "Parent (Sub)" display never needs the full ancestor chain.
      parent: { select: { id: true, name: true } },
    },
  },
  images: { orderBy: { sortOrder: 'asc' } },
  // Descriptive metadata only (NOT variants) — never read by inventory/ledger code.
  attributes: { include: { attributeType: true }, orderBy: { attributeType: { name: 'asc' } } },
};

function createProductsService({ prisma, cache, config, categories, attributeTypes, workstreamManagers }) {
  // A product embeds totalOnHand (ledger-derived), so its cached reads die on catalogue AND stock writes.
  const readTags = [TAGS.CATALOGUE, TAGS.STOCK];
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  /**
   * Sum of on_hand across every ACTIVE location, batched for a whole result set in ONE groupBy —
   * never N+1, never a full-table fetch summed in JS. Read straight off inventory_balances (never
   * written here — rule 2 is about writes) which also avoids a circular module dependency.
   */
  async function attachTotalOnHand(products) {
    if (products.length === 0) return [];

    const totals = await prisma.inventoryBalance.groupBy({
      by: ['productId'],
      where: { productId: { in: products.map((p) => p.id) }, location: { isActive: true } },
      _sum: { onHand: true },
    });
    const totalByProductId = new Map(totals.map((t) => [t.productId, Number(t._sum.onHand ?? 0)]));
    return products.map((p) => ({ ...p, totalOnHand: totalByProductId.get(p.id) ?? 0 }));
  }

  /** Same intersection logic as the categories service: explicit filter ∩ the viewer's assigned workstreams. */
  async function effectiveWorkstreamIdFilter(explicit, viewerId) {
    if (!viewerId) return explicit;
    const assignedIds = await workstreamManagers.getAssignedWorkstreamIds(viewerId);
    if (assignedIds.length === 0) return explicit;
    if (!explicit) return { in: assignedIds };
    return assignedIds.includes(explicit) ? explicit : { in: [] };
  }

  async function queryProducts(query, workstreamId) {
    const where = {
      categoryId: query.categoryId,
      status: query.status ?? (query.includeInactive ? undefined : ProductStatus.ACTIVE),
      // Product has no workstream_id of its own — it is implied by its category's.
      category: workstreamId ? { workstreamId } : undefined,
    };

    if (query.search) {
      // No `mode: 'insensitive'` on MySQL/MariaDB (Postgres-only); the default *_ci collation already
      // makes LIKE/contains case-insensitive.
      where.OR = [{ sku: { contains: query.search } }, { name: { contains: query.search } }];
    }

    // `?attribute=Colour:Red` — matched by the attribute TYPE's name (not code), split on the FIRST
    // colon so a value containing ":" still works.
    if (query.attribute) {
      const separatorIndex = query.attribute.indexOf(':');
      if (separatorIndex > 0) {
        const name = query.attribute.slice(0, separatorIndex).trim();
        const value = query.attribute.slice(separatorIndex + 1).trim();
        where.attributes = { some: { attributeType: { name }, value } };
      }
    }

    const products = await prisma.product.findMany({ where, include: PRODUCT_INCLUDE, orderBy: { name: 'asc' } });
    return attachTotalOnHand(products);
  }

  /**
   * [viewerId], when given, narrows the result to products whose category is in a workstream that
   * viewer is assigned to. Free-text searches are NOT cached (unbounded key space); the plain
   * list/filter views the screens open on are.
   */
  async function findAll(query = {}, viewerId) {
    const workstreamId = await effectiveWorkstreamIdFilter(query.workstreamId, viewerId);
    if (query.search) return queryProducts(query, workstreamId);

    const wsKey = workstreamId && typeof workstreamId === 'object' ? `in:${workstreamId.in.join(',')}` : (workstreamId ?? '-');
    const key = [
      'products:list',
      query.categoryId ?? '-',
      wsKey,
      query.status ?? '-',
      query.includeInactive ? 'all' : 'active',
      query.attribute ?? '-',
    ].join(':');
    return cache.wrap(key, { ttlMs: config.cache.catalogueTtlMs, tags: readTags }, () => queryProducts(query, workstreamId));
  }

  // Never cached: writers and audit old-values must see the row as it is right now.
  async function getExisting(id) {
    const product = await prisma.product.findUnique({ where: { id }, include: PRODUCT_INCLUDE });
    if (!product) throw notFound(`Product ${id} not found`);
    const [withTotal] = await attachTotalOnHand([product]);
    return withTotal;
  }

  /** Cheap existence check (no includes, no stock aggregate) for callers that only need a 404. */
  async function assertExists(id) {
    const product = await prisma.product.findUnique({ where: { id }, select: { id: true } });
    if (!product) throw notFound(`Product ${id} not found`);
  }

  /** One query for a whole list of ids (used by stock counts); 404s naming the first missing id. */
  async function assertAllExist(ids) {
    const unique = [...new Set(ids)];
    const found = await prisma.product.findMany({ where: { id: { in: unique } }, select: { id: true } });
    if (found.length === unique.length) return;
    const foundIds = new Set(found.map((p) => p.id));
    throw notFound(`Product ${unique.find((id) => !foundIds.has(id))} not found`);
  }

  /** [viewerId], when given, 403s if that viewer is scoped and this product's workstream isn't one of theirs. */
  async function findOne(id, viewerId) {
    const product = await cache.wrap(`products:one:${id}`, { ttlMs: config.cache.catalogueTtlMs, tags: readTags }, () =>
      getExisting(id),
    );
    if (viewerId) await workstreamManagers.assertScopedAccess(viewerId, product.category.workstreamId);
    return product;
  }

  /** Bulk existing-product lookup by SKU (active or not) — one query for a whole import file. */
  function findManyBySkus(skus) {
    if (skus.length === 0) return Promise.resolve([]);
    return prisma.product.findMany({ where: { sku: { in: skus } }, include: PRODUCT_INCLUDE });
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  const countActive = () => prisma.product.count({ where: { status: ProductStatus.ACTIVE } });

  function coerceAttributeValue(attributeType, raw) {
    if (attributeType.dataType === 'NUMBER') {
      const num = typeof raw === 'number' ? raw : Number(raw);
      if (raw === '' || raw === null || Number.isNaN(num)) {
        throw badRequest(`Attribute "${attributeType.name}" expects a number`);
      }
      // Canonical string form — the same shape Decimal columns already serialise as on read.
      return String(num);
    }
    const text = String(raw).trim();
    if (!text) throw badRequest(`Attribute "${attributeType.name}" cannot be empty`);
    return text;
  }

  /**
   * Validates and normalises a create/update `attributes` array: every attributeTypeId must exist,
   * at most once each, and its value must fit the type's dataType. Returns `undefined` when the
   * input is undefined (caller: "don't touch attributes"), distinct from `[]` ("clear them all").
   */
  async function resolveAttributes(inputs) {
    if (inputs === undefined || inputs === null) return undefined;

    const seen = new Set();
    const resolved = [];
    for (const input of inputs) {
      if (seen.has(input.attributeTypeId)) {
        throw badRequest('Duplicate attributeTypeId in attributes — a product has only one value per attribute type');
      }
      seen.add(input.attributeTypeId);

      const attributeType = await attributeTypes.getExisting(input.attributeTypeId);
      resolved.push({ attributeTypeId: input.attributeTypeId, value: coerceAttributeValue(attributeType, input.value) });
    }
    return resolved;
  }

  async function create(dto, actingUserId) {
    const category = await categories.getExisting(dto.categoryId);
    await workstreamManagers.assertScopedAccess(actingUserId, category.workstreamId);

    const existingSku = await prisma.product.findUnique({ where: { sku: dto.sku } });
    if (existingSku) throw conflict('A product with this SKU already exists');

    const attributes = await resolveAttributes(dto.attributes);

    const productId = await prisma.$transaction(async (tx) => {
      const product = await tx.product.create({
        data: {
          sku: dto.sku,
          name: dto.name,
          description: dto.description,
          categoryId: dto.categoryId,
          sellingPrice: dto.sellingPrice,
          costPrice: dto.costPrice,
          uom: dto.uom,
          minStockLevel: dto.minStockLevel ?? 0,
        },
      });
      if (attributes?.length) {
        await tx.productAttribute.createMany({ data: attributes.map((a) => ({ productId: product.id, ...a })) });
      }
      return product.id;
    });

    await invalidate();
    return getExisting(productId);
  }

  async function update(id, dto, actingUserId) {
    const existing = await getExisting(id);
    // Scoped to the product's CURRENT workstream (via its category) always — moving it to a new
    // category additionally requires scope over the DESTINATION category's workstream.
    await workstreamManagers.assertScopedAccess(actingUserId, existing.category.workstreamId);

    if (dto.categoryId) {
      const newCategory = await categories.getExisting(dto.categoryId);
      await workstreamManagers.assertScopedAccess(actingUserId, newCategory.workstreamId);
    }

    const attributes = await resolveAttributes(dto.attributes);

    await prisma.$transaction(async (tx) => {
      await tx.product.update({
        where: { id },
        data: {
          name: dto.name ?? undefined,
          description: dto.description,
          categoryId: dto.categoryId ?? undefined,
          sellingPrice: dto.sellingPrice ?? undefined,
          costPrice: dto.costPrice,
          uom: dto.uom ?? undefined,
          minStockLevel: dto.minStockLevel ?? undefined,
          status: dto.status ?? undefined,
        },
      });

      // Only touch attributes when the field was explicitly provided — omitted leaves the existing
      // set untouched; `[]` deliberately clears it; otherwise it REPLACES the full set.
      if (attributes !== undefined) {
        await tx.productAttribute.deleteMany({ where: { productId: id } });
        if (attributes.length) {
          await tx.productAttribute.createMany({ data: attributes.map((a) => ({ productId: id, ...a })) });
        }
      }
    });

    await invalidate();
    return getExisting(id);
  }

  async function remove(id, actingUserId) {
    const existing = await getExisting(id);
    await workstreamManagers.assertScopedAccess(actingUserId, existing.category.workstreamId);
    // Reference data is soft-deleted (rule 10) — orders/inventory transactions keep a valid historical reference.
    await prisma.product.update({ where: { id }, data: { status: ProductStatus.INACTIVE } });
    await invalidate();
    return getExisting(id);
  }

  return { findAll, findOne, getExisting, assertExists, assertAllExist, findManyBySkus, countActive, create, update, remove, invalidate };
}

module.exports = { createProductsService, PRODUCT_INCLUDE };
