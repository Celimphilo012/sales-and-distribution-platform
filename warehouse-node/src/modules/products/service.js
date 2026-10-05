'use strict';

const { ProductStatus } = require('../../core/enums');
const { badRequest, conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, nest, groupBy, Where } = require('../../core/models');

/**
 * A product read is: the product row + category { id, name, workstreamId, workstream { id, name,
 * code, warehouseId }, parent { id, name } | null } + images (by sortOrder) + attributes (each with its full
 * attributeType, by type name). The category chain is one joined query; images and attributes are
 * one batched query each for the whole result set — never one query per product.
 */
const PRODUCT_SELECT = `
  SELECT ${cols('product', 'p')},
         ${cols('category', 'c', ['id', 'name', 'workstreamId'], 'category.')},
         ${cols('workstream', 'w', ['id', 'name', 'code', 'warehouseId'], 'category.workstream.')},
         ${cols('category', 'pc', ['id', 'name'], 'category.parent.')}
    FROM products p
    JOIN categories c ON c.id = p.category_id
    JOIN workstreams w ON w.id = c.workstream_id
    LEFT JOIN categories pc ON pc.id = c.parent_id`;

/** LIKE pattern for a "contains" search, with the user's own % and _ matched literally. */
const containsPattern = (text) => `%${text.replace(/[\\%_]/g, '\\$&')}%`;

function createProductsService({
  db,
  models,
  cache,
  config,
  access,
  categories,
  workstreams,
  attributeTypes,
  workstreamManagers,
}) {
  // A product embeds totalOnHand (ledger-derived), so its cached reads die on catalogue AND stock writes.
  const readTags = [TAGS.CATALOGUE, TAGS.STOCK];
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  /** Runs PRODUCT_SELECT with a WHERE clause and attaches images + attributes. */
  async function loadProducts(where = new Where(), orderBy = 'ORDER BY p.name ASC') {
    const products = (await db.query(`${PRODUCT_SELECT} ${where.sql} ${orderBy}`, where.params)).map(nest);
    if (products.length === 0) return products;
    const ids = products.map((p) => p.id);

    const [images, attributes] = await Promise.all([
      db.query(`SELECT ${cols('productImage', 'i')} FROM product_images i WHERE i.product_id IN (?) ORDER BY i.sort_order ASC`, [ids]),
      db.query(
        `SELECT ${cols('productAttribute', 'pa')}, ${cols('attributeType', 'aty', undefined, 'attributeType.')}
           FROM product_attributes pa
           JOIN attribute_types aty ON aty.id = pa.attribute_type_id
          WHERE pa.product_id IN (?)
          ORDER BY aty.name ASC`,
        [ids],
      ),
    ]);
    const imagesByProduct = groupBy(images, 'productId');
    const attributesByProduct = groupBy(attributes.map(nest), 'productId');

    return products.map((p) => ({
      ...p,
      images: imagesByProduct.get(p.id) ?? [],
      // Descriptive metadata only (NOT variants) — never read by inventory/ledger code.
      attributes: attributesByProduct.get(p.id) ?? [],
    }));
  }

  /**
   * Sum of on_hand across every ACTIVE location, batched for a whole result set in ONE grouped
   * query — never N+1, never a full-table fetch summed in JS. Read straight off inventory_balances
   * (never written here — rule 2 is about writes) which also avoids a circular module dependency.
   */
  async function attachTotalOnHand(products) {
    if (products.length === 0) return [];

    const totals = await db.query(
      `SELECT ib.product_id AS productId, SUM(ib.on_hand) AS onHand
         FROM inventory_balances ib
         JOIN locations l ON l.id = ib.location_id AND l.is_active = true
        WHERE ib.product_id IN (?)
        GROUP BY ib.product_id`,
      [products.map((p) => p.id)],
    );
    const totalByProductId = new Map(totals.map((t) => [t.productId, Number(t.onHand ?? 0)]));
    return products.map((p) => ({ ...p, totalOnHand: totalByProductId.get(p.id) ?? 0 }));
  }

  /** PERCENT/FIXED_AMOUNT/FIXED_PRICE -> a price, never negative. 2dp, same as every other price. */
  function discountedPrice(sellingPrice, discountType, discountValue) {
    const raw =
      discountType === 'PERCENT'
        ? sellingPrice * (1 - discountValue / 100)
        : discountType === 'FIXED_AMOUNT'
          ? sellingPrice - discountValue
          : discountValue; // FIXED_PRICE
    return Math.max(0, Math.round(raw * 100) / 100);
  }

  /**
   * Attaches `sale` (this product's terms on whatever campaign currently has it ACTIVE — at most
   * one, since a product sits on only one PENDING_APPROVAL/SCHEDULED/ACTIVE campaign at a time;
   * see sales/service.js's assertNoOverlap). Batched for the whole result set, same shape as
   * attachTotalOnHand. `effectivePrice` is only resolved for an ALL_CUSTOMERS campaign — a
   * RESTRICTED one depends on which customer is asking, which this service never learns (see
   * ARCHITECTURE.md: eligibility is resolved entirely on the ordering side).
   */
  async function attachActiveSale(products) {
    if (products.length === 0) return [];
    const rows = await db.query(
      `SELECT cp.product_id AS productId, cp.discount_type AS discountType, cp.discount_value AS discountValue,
              cp.min_quantity AS minQuantity, s.id AS campaignId, s.name AS campaignName, s.eligibility,
              s.max_uses_per_customer AS maxUsesPerCustomer
         FROM sale_campaign_products cp
         JOIN sale_campaigns s ON s.id = cp.campaign_id AND s.status = 'ACTIVE'
        WHERE cp.product_id IN (?)`,
      [products.map((p) => p.id)],
    );
    const byProductId = new Map(rows.map((r) => [r.productId, r]));
    return products.map((p) => {
      const row = byProductId.get(p.id);
      if (!row) return p;
      const discountValue = Number(row.discountValue);
      return {
        ...p,
        sale: {
          campaignId: row.campaignId,
          campaignName: row.campaignName,
          discountType: row.discountType,
          discountValue,
          minQuantity: Number(row.minQuantity),
          eligibility: row.eligibility,
          maxUsesPerCustomer: row.maxUsesPerCustomer === null ? undefined : Number(row.maxUsesPerCustomer),
          effectivePrice: row.eligibility === 'ALL_CUSTOMERS' ? discountedPrice(Number(p.sellingPrice), row.discountType, discountValue) : undefined,
        },
      };
    });
  }

  /** Same intersection logic as the categories service: explicit filter ∩ the viewer's assigned workstreams. */
  async function effectiveWorkstreamIdFilter(explicit, viewerId) {
    if (!viewerId) return explicit;
    const assignedIds = await workstreamManagers.getAssignedWorkstreamIds(viewerId);
    if (assignedIds.length === 0) return explicit;
    if (!explicit) return { in: assignedIds };
    return assignedIds.includes(explicit) ? explicit : { in: [] };
  }

  async function queryProducts(query, workstreamId, warehouseIds) {
    const where = new Where()
      .eq('p.category_id', query.categoryId)
      .in('w.warehouse_id', warehouseIds ?? undefined)
      .eq('p.status', query.status ?? (query.includeInactive ? undefined : ProductStatus.ACTIVE));

    // Product has no workstream_id of its own — it is implied by its category's.
    if (workstreamId && typeof workstreamId === 'object') where.in('c.workstream_id', workstreamId.in);
    else if (workstreamId) where.eq('c.workstream_id', workstreamId);

    if (query.search) {
      // The default *_ci collation already makes LIKE case-insensitive.
      const pattern = containsPattern(query.search);
      where.raw('(p.sku LIKE ? OR p.name LIKE ?)', pattern, pattern);
    }

    // `?attribute=Colour:Red` — matched by the attribute TYPE's name (not code), split on the FIRST
    // colon so a value containing ":" still works.
    if (query.attribute) {
      const separatorIndex = query.attribute.indexOf(':');
      if (separatorIndex > 0) {
        const name = query.attribute.slice(0, separatorIndex).trim();
        const value = query.attribute.slice(separatorIndex + 1).trim();
        where.raw(
          `EXISTS (SELECT 1 FROM product_attributes fa JOIN attribute_types ft ON ft.id = fa.attribute_type_id
                    WHERE fa.product_id = p.id AND ft.name = ? AND fa.value = ?)`,
          name,
          value,
        );
      }
    }

    return attachActiveSale(await attachTotalOnHand(await loadProducts(where)));
  }

  /**
   * [viewerId], when given, narrows the result to the viewer's warehouses (modules/access), then to
   * products whose category is in a workstream that viewer is assigned to manage (if any). Free-text searches are NOT cached (unbounded key space); the plain
   * list/filter views the screens open on are.
   */
  async function findAll(query = {}, viewerId) {
    const [workstreamId, warehouseIds] = await Promise.all([
      effectiveWorkstreamIdFilter(query.workstreamId, viewerId),
      access.warehouseScope(viewerId),
    ]);
    if (query.search) return queryProducts(query, workstreamId, warehouseIds);

    const wsKey = workstreamId && typeof workstreamId === 'object' ? `in:${workstreamId.in.join(',')}` : (workstreamId ?? '-');
    const key = [
      'products:list',
      query.categoryId ?? '-',
      wsKey,
      query.status ?? '-',
      query.includeInactive ? 'all' : 'active',
      query.attribute ?? '-',
      access.scopeKey(warehouseIds),
    ].join(':');
    return cache.wrap(key, { ttlMs: config.cache.catalogueTtlMs, tags: readTags }, () =>
      queryProducts(query, workstreamId, warehouseIds),
    );
  }

  // Never cached: writers and audit old-values must see the row as it is right now.
  async function getExisting(id) {
    const [product] = await loadProducts(new Where().eq('p.id', id), '');
    if (!product) throw notFound(`Product ${id} not found`);
    const [withTotal] = await attachTotalOnHand([product]);
    const [withSale] = await attachActiveSale([withTotal]);
    return withSale;
  }

  /** 404 unless the product exists; 403 unless `userId` may access its warehouse (no userId = unscoped). */
  async function assertAccessible(id, userId) {
    const row = await db.one(
      `SELECT w.warehouse_id AS warehouseId FROM products p
         JOIN categories c ON c.id = p.category_id JOIN workstreams w ON w.id = c.workstream_id
        WHERE p.id = ?`,
      [id],
    );
    if (!row) throw notFound(`Product ${id} not found`);
    await access.assertWarehouse(userId, row.warehouseId);
  }

  /** Cheap existence check (no joins, no stock aggregate) for callers that only need a 404. */
  async function assertExists(id) {
    const product = await db.one('SELECT id FROM products WHERE id = ?', [id]);
    if (!product) throw notFound(`Product ${id} not found`);
  }

  /** One query for a whole list of ids (used by stock counts); 404s naming the first missing id. */
  async function assertAllExist(ids) {
    const unique = [...new Set(ids)];
    const found = await db.query('SELECT id FROM products WHERE id IN (?)', [unique]);
    if (found.length === unique.length) return;
    const foundIds = new Set(found.map((p) => p.id));
    throw notFound(`Product ${unique.find((id) => !foundIds.has(id))} not found`);
  }

  /** [viewerId], when given, 403s if that viewer is scoped and this product's workstream isn't one of theirs. */
  async function findOne(id, viewerId) {
    const product = await cache.wrap(`products:one:${id}`, { ttlMs: config.cache.catalogueTtlMs, tags: readTags }, () =>
      getExisting(id),
    );
    await access.assertWarehouse(viewerId, product.category.workstream.warehouseId);
    if (viewerId) await workstreamManagers.assertScopedAccess(viewerId, product.category.workstreamId);
    return product;
  }

  /** Bulk existing-product lookup by SKU (active or not) — one query for a whole import file. */
  function findManyBySkus(skus) {
    if (skus.length === 0) return Promise.resolve([]);
    return loadProducts(new Where().in('p.sku', skus), '');
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary, within the given warehouses (null = all). */
  async function countActive(warehouseIds = null) {
    const where = new Where().eq('p.status', ProductStatus.ACTIVE).in('w.warehouse_id', warehouseIds ?? undefined);
    const row = await db.one(
      `SELECT COUNT(*) AS n FROM products p
         JOIN categories c ON c.id = p.category_id JOIN workstreams w ON w.id = c.workstream_id ${where.sql}`,
      where.params,
    );
    return Number(row.n);
  }

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
    await workstreams.getAccessible(category.workstreamId, actingUserId);
    await workstreamManagers.assertScopedAccess(actingUserId, category.workstreamId);

    const existingSku = await db.one('SELECT id FROM products WHERE sku = ?', [dto.sku]);
    if (existingSku) throw conflict('A product with this SKU already exists');

    const attributes = await resolveAttributes(dto.attributes);

    const productId = await db.transaction(async (tx) => {
      const product = await models.insert(
        'product',
        {
          sku: dto.sku,
          name: dto.name,
          description: dto.description,
          categoryId: dto.categoryId,
          sellingPrice: dto.sellingPrice,
          costPrice: dto.costPrice,
          uom: dto.uom,
          minStockLevel: dto.minStockLevel ?? 0,
          trackingMode: dto.trackingMode ?? 'BULK',
        },
        tx,
      );
      if (attributes?.length) {
        await models.insertMany('productAttribute', attributes.map((a) => ({ productId: product.id, ...a })), tx);
      }
      return product.id;
    });

    await invalidate();
    return getExisting(productId);
  }

  async function update(id, dto, actingUserId) {
    const existing = await getExisting(id);
    await access.assertWarehouse(actingUserId, existing.category.workstream.warehouseId);
    // Scoped to the product's CURRENT workstream (via its category) always — moving it to a new
    // category additionally requires scope over the DESTINATION category's workstream.
    await workstreamManagers.assertScopedAccess(actingUserId, existing.category.workstreamId);

    if (dto.categoryId) {
      const newCategory = await categories.getExisting(dto.categoryId);
      await workstreams.getAccessible(newCategory.workstreamId, actingUserId);
      await workstreamManagers.assertScopedAccess(actingUserId, newCategory.workstreamId);
    }

    const sku = dto.sku?.trim();
    if (sku && sku !== existing.sku) {
      const clash = await db.one('SELECT id FROM products WHERE sku = ? AND id <> ?', [sku, id]);
      if (clash) throw conflict('A product with this SKU already exists');
    }

    const attributes = await resolveAttributes(dto.attributes);

    await db.transaction(async (tx) => {
      await models.update(
        'product',
        id,
        {
          sku: sku || undefined,
          name: dto.name ?? undefined,
          description: dto.description,
          categoryId: dto.categoryId ?? undefined,
          sellingPrice: dto.sellingPrice ?? undefined,
          costPrice: dto.costPrice,
          uom: dto.uom ?? undefined,
          minStockLevel: dto.minStockLevel ?? undefined,
          status: dto.status ?? undefined,
          trackingMode: dto.trackingMode ?? undefined,
        },
        'Product',
        tx,
      );

      // Only touch attributes when the field was explicitly provided — omitted leaves the existing
      // set untouched; `[]` deliberately clears it; otherwise it REPLACES the full set.
      if (attributes !== undefined) {
        await db.exec('DELETE FROM product_attributes WHERE product_id = ?', [id], tx);
        if (attributes.length) {
          await models.insertMany('productAttribute', attributes.map((a) => ({ productId: id, ...a })), tx);
        }
      }
    });

    await invalidate();
    return getExisting(id);
  }

  async function remove(id, actingUserId) {
    const existing = await getExisting(id);
    await access.assertWarehouse(actingUserId, existing.category.workstream.warehouseId);
    await workstreamManagers.assertScopedAccess(actingUserId, existing.category.workstreamId);
    // Reference data is soft-deleted (rule 10) — orders/inventory transactions keep a valid historical reference.
    await models.update('product', id, { status: ProductStatus.INACTIVE }, 'Product');
    await invalidate();
    return getExisting(id);
  }

  return { findAll, findOne, getExisting, assertExists, assertAccessible, assertAllExist, findManyBySkus, countActive, create, update, remove, invalidate };
}

module.exports = { createProductsService };
