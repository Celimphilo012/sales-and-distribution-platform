"use strict";
exports.ProductImportService = void 0;
const { HttpError, notFound } = require('../../core/errors');
const client_1 = require("@prisma/client");
const spreadsheet_reader_1 = require("./parsing/spreadsheet-reader");
const strict_number_1 = require("./parsing/strict-number");
const build_import_template_1 = require("./template/build-import-template");
const FIXED_HEADERS = new Set([
    'sku',
    'name',
    'description',
    'workstream_code',
    'category_name',
    'selling_price',
    'cost_price',
    'uom',
    'min_stock_level',
]);
/** How the template names an attribute column — the same computation the template builder uses, so upload matching lines up with what was downloaded. */
function attributeHeader(attributeType) {
    return attributeType.unit ? `${attributeType.name} (${attributeType.unit})` : attributeType.name;
}
class ProductImportService {
    constructor(productsService, categoriesService, workstreamsService, workstreamManagersService, attributeTypesService, warehousesService, sessions) {
        this.productsService = productsService;
        this.categoriesService = categoriesService;
        this.workstreamsService = workstreamsService;
        this.workstreamManagersService = workstreamManagersService;
        this.attributeTypesService = attributeTypesService;
        this.warehousesService = warehousesService;
        this.sessions = sessions;
    }
    // -----------------------------------------------------------------
    // 1. Template
    // -----------------------------------------------------------------
    /** [userId]'s example rows are drawn only from their assigned workstream(s) when they're scoped — same restriction as the actual import. */
    async buildTemplate(userId) {
        const attributeTypes = await this.attributeTypesService.findAll({ includeInactive: false });
        const attributeColumns = attributeTypes.map((a) => ({
            header: attributeHeader(a),
            dataType: a.dataType,
        }));
        const examples = await this.buildExampleRows(attributeTypes, userId);
        return (0, build_import_template_1.buildImportTemplate)(attributeColumns, examples);
    }
    /**
     * Picks up to two REAL active (workstream, category) pairs to build
     * genuinely-valid example rows from — so the template is immediately
     * re-uploadable as a working demonstration, and never goes stale by
     * naming a workstream/category that doesn't exist in whatever catalogue
     * is actually live when it's downloaded.
     */
    async buildExampleRows(attributeTypes, userId) {
        const scopedIds = await this.workstreamManagersService.getAssignedWorkstreamIds(userId);
        let activeWorkstreams = await this.getActiveWorkstreams();
        if (scopedIds.length > 0) {
            const scoped = new Set(scopedIds);
            activeWorkstreams = activeWorkstreams.filter((w) => scoped.has(w.id));
        }
        const activeWorkstreamIds = new Set(activeWorkstreams.map((w) => w.id));
        const workstreamById = new Map(activeWorkstreams.map((w) => [w.id, w]));
        const allActiveCategories = await this.categoriesService.findAll({ includeInactive: false });
        const categories = allActiveCategories
            .filter((c) => activeWorkstreamIds.has(c.workstreamId))
            .sort((a, b) => a.workstreamId.localeCompare(b.workstreamId) || a.name.localeCompare(b.name))
            .slice(0, 2);
        if (categories.length === 0)
            return [];
        const sampleAttributeValues = (seed) => {
            const values = {};
            for (const attributeType of attributeTypes) {
                const header = attributeHeader(attributeType);
                if (attributeType.dataType === 'NUMBER') {
                    if (attributeType.name.toLowerCase() === 'weight')
                        values[header] = seed === 0 ? '0.5' : '0.12';
                }
                else if (attributeType.name.toLowerCase() === 'colour') {
                    values[header] = seed === 0 ? 'Blue' : 'Ivory';
                }
                else if (attributeType.name.toLowerCase() === 'brand') {
                    values[header] = seed === 0 ? 'HomeFresh' : 'Aroma Naturals';
                }
            }
            return values;
        };
        const rows = [
            {
                sku: 'IMP-EXAMPLE-001',
                name: 'All-Purpose Cleaner Spray 500ml',
                description: 'Multi-surface cleaning spray, 500ml trigger bottle',
                workstreamCode: workstreamById.get(categories[0].workstreamId).code,
                categoryName: categories[0].name,
                sellingPrice: 45.0,
                costPrice: 28.5,
                uom: 'EACH',
                minStockLevel: 10,
                attributeValues: sampleAttributeValues(0),
            },
        ];
        if (categories[1]) {
            rows.push({
                sku: 'IMP-EXAMPLE-002',
                name: 'Sandalwood Bar Soap 100g',
                workstreamCode: workstreamById.get(categories[1].workstreamId).code,
                categoryName: categories[1].name,
                sellingPrice: 22.0,
                uom: 'EACH',
                minStockLevel: 25,
                attributeValues: sampleAttributeValues(1),
            });
        }
        return rows;
    }
    // -----------------------------------------------------------------
    // 2. Preview
    // -----------------------------------------------------------------
    async preview(file, userId) {
        const rawRows = await (0, spreadsheet_reader_1.readSpreadsheetRows)(file.buffer, file.originalname);
        const context = await this.buildValidationContext(rawRows, userId);
        const { creates, rejected } = this.validateAndDedupe(rawRows, context);
        const toCreate = [];
        const toUpdate = [];
        for (const row of creates.values()) {
            const existing = context.existingBySku.get(row.sku);
            if (existing) {
                toUpdate.push({ ...row, existingProductId: existing.id, changes: this.computeChanges(existing, row) });
            }
            else {
                toCreate.push(row);
            }
        }
        toCreate.sort((a, b) => a.rowNumber - b.rowNumber);
        toUpdate.sort((a, b) => a.rowNumber - b.rowNumber);
        rejected.sort((a, b) => a.rowNumber - b.rowNumber);
        const session = this.sessions.create(userId, file.originalname, toCreate, toUpdate);
        return {
            importSessionId: session.id,
            fileName: file.originalname,
            toCreate,
            toUpdate,
            rejected,
            summary: {
                createCount: toCreate.length,
                updateCount: toUpdate.length,
                rejectCount: rejected.length,
                totalRows: rawRows.length,
            },
        };
    }
    // -----------------------------------------------------------------
    // 3. Confirm
    // -----------------------------------------------------------------
    async confirm(importSessionId, userId) {
        const session = this.sessions.take(importSessionId);
        if (!session) {
            throw notFound('This import session has expired or was already confirmed — upload the file again for a fresh preview.');
        }
        // Single-use regardless of outcome below — a stale preview should never
        // be replayable, and a failed confirm should be retried via a fresh
        // upload/preview so it re-validates against current data.
        this.sessions.discard(importSessionId);
        const failed = [];
        let created = 0;
        let updated = 0;
        for (const row of session.toCreate) {
            const reason = await this.revalidateStillActive(row);
            if (reason) {
                failed.push({ sku: row.sku, reason });
                continue;
            }
            try {
                await this.productsService.create({
                    sku: row.sku,
                    name: row.name,
                    description: row.description,
                    categoryId: row.categoryId,
                    sellingPrice: row.sellingPrice,
                    costPrice: row.costPrice,
                    uom: row.uom,
                    minStockLevel: row.minStockLevel,
                    attributes: row.attributes.map((a) => ({ attributeTypeId: a.attributeTypeId, value: a.value })),
                }, userId);
                created++;
            }
            catch (error) {
                failed.push({ sku: row.sku, reason: this.describeWriteError(error) });
            }
        }
        for (const row of session.toUpdate) {
            const reason = await this.revalidateStillActive(row);
            if (reason) {
                failed.push({ sku: row.sku, reason });
                continue;
            }
            try {
                await this.productsService.update(row.existingProductId, {
                    name: row.name,
                    description: row.description,
                    categoryId: row.categoryId,
                    sellingPrice: row.sellingPrice,
                    costPrice: row.costPrice,
                    uom: row.uom,
                    minStockLevel: row.minStockLevel,
                    // Full replace ("same as PATCH", per the task) — a blank
                    // attribute column in the import row means that attribute is
                    // CLEARED if the existing product had a value; documented on the
                    // template's Instructions sheet.
                    attributes: row.attributes.map((a) => ({ attributeTypeId: a.attributeTypeId, value: a.value })),
                }, userId);
                updated++;
            }
            catch (error) {
                failed.push({ sku: row.sku, reason: this.describeWriteError(error) });
            }
        }
        // Who imported is already on the audit_logs row via request.user;
        // created/updated/failed counts + the file name are attached by the
        // controller (see ProductImportController.confirm) so they land in the
        // same row's newValue instead of a second write.
        return { created, updated, failed, fileName: session.fileName };
    }
    describeWriteError(error) {
        if (error instanceof client_1.Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
            return 'A product with this SKU already exists';
        }
        if ((error instanceof HttpError && error.statusCode === 404)) {
            return error.message;
        }
        return error instanceof Error ? error.message : 'Could not save this row';
    }
    /**
     * Defensive re-check the task specifically asks for: "in case a category
     * was deleted between preview and confirm". Products/categories/
     * workstreams/attribute-types are all soft-deleted (rule 10) — real
     * deletion never happens — so the realistic version of that scenario is
     * DEACTIVATION, which is exactly what `ProductsService.create/update`
     * does NOT check (their `getExisting()` calls only check existence, not
     * `isActive`). This is the actual gap this step closes; existence/
     * uniqueness failures are left to `create`/`update` themselves (caught by
     * `describeWriteError` above) rather than duplicated here.
     */
    async revalidateStillActive(row) {
        const workstream = await this.workstreamsService.getExisting(row.workstreamId).catch(() => null);
        if (!workstream || !workstream.isActive) {
            return `Workstream "${row.workstreamCode}" is no longer active — it changed since you previewed this import`;
        }
        const warehouse = await this.warehousesService.getExisting(workstream.warehouseId).catch(() => null);
        if (!warehouse || !warehouse.isActive) {
            return `Workstream "${row.workstreamCode}"'s warehouse is no longer active — it changed since you previewed this import`;
        }
        const category = await this.categoriesService.getExisting(row.categoryId).catch(() => null);
        if (!category || !category.isActive || category.workstreamId !== row.workstreamId) {
            return `Category "${row.categoryName}" is no longer available in workstream "${row.workstreamCode}" — it changed since you previewed this import`;
        }
        for (const attribute of row.attributes) {
            const attributeType = await this.attributeTypesService.getExisting(attribute.attributeTypeId).catch(() => null);
            if (!attributeType || !attributeType.isActive) {
                return `Attribute type "${attribute.name}" is no longer active — it changed since you previewed this import`;
            }
        }
        return null;
    }
    // -----------------------------------------------------------------
    // Row validation (preview time)
    // -----------------------------------------------------------------
    /** Active workstreams whose warehouse is ALSO active — `WorkstreamsService.findAll()` only filters the workstream's own `isActive`, not its warehouse's (the two are independent soft-deletes), so this cross-references both. */
    async getActiveWorkstreams() {
        const [workstreams, warehouses] = await Promise.all([
            this.workstreamsService.findAll({ includeInactive: false }),
            this.warehousesService.findAll({ includeInactive: false }),
        ]);
        const activeWarehouseIds = new Set(warehouses.map((w) => w.id));
        return workstreams
            .filter((w) => activeWarehouseIds.has(w.warehouseId))
            .map((w) => ({ id: w.id, code: w.code, name: w.name, warehouseId: w.warehouseId }));
    }
    async buildValidationContext(rows, userId) {
        const [activeWorkstreams, categories, attributeTypes, scopedIds] = await Promise.all([
            this.getActiveWorkstreams(),
            this.categoriesService.findAll({ includeInactive: false }),
            this.attributeTypesService.findAll({ includeInactive: false }),
            this.workstreamManagersService.getAssignedWorkstreamIds(userId),
        ]);
        const scopedWorkstreamIds = scopedIds.length === 0 ? null : new Set(scopedIds);
        const workstreamsByCode = new Map();
        for (const w of activeWorkstreams) {
            // Codes are only unique PER WAREHOUSE (schema: @@unique([warehouseId,
            // code])), not globally — with more than one active warehouse two
            // could collide. Currently there's exactly one active warehouse, so
            // this never fires in practice, but a collision is reported per-row
            // rather than silently picking one.
            workstreamsByCode.set(w.code, workstreamsByCode.has(w.code) ? '__AMBIGUOUS__' : w);
        }
        const categoriesByWorkstream = new Map();
        for (const c of categories) {
            const list = categoriesByWorkstream.get(c.workstreamId) ?? [];
            list.push({ id: c.id, name: c.name, workstreamId: c.workstreamId });
            categoriesByWorkstream.set(c.workstreamId, list);
        }
        const attributeTypesByHeader = new Map();
        for (const a of attributeTypes) {
            attributeTypesByHeader.set(attributeHeader(a), { id: a.id, name: a.name, dataType: a.dataType, header: attributeHeader(a) });
        }
        const skusInFile = new Set();
        for (const row of rows) {
            const sku = String(row.cells['sku'] ?? '').trim();
            if (sku)
                skusInFile.add(sku);
        }
        const existingProducts = await this.productsService.findManyBySkus([...skusInFile]);
        const existingBySku = new Map();
        for (const p of existingProducts) {
            existingBySku.set(p.sku, {
                id: p.id,
                name: p.name,
                description: p.description,
                categoryId: p.categoryId,
                categoryName: p.category.name,
                workstreamName: p.category.workstream.name,
                sellingPrice: Number(p.sellingPrice),
                costPrice: p.costPrice === null ? null : Number(p.costPrice),
                uom: p.uom,
                minStockLevel: Number(p.minStockLevel),
                attributes: p.attributes.map((a) => ({ attributeTypeId: a.attributeTypeId, name: a.attributeType.name, value: a.value })),
            });
        }
        return { workstreamsByCode, categoriesByWorkstream, attributeTypesByHeader, existingBySku, scopedWorkstreamIds };
    }
    /** Validates every row, then dedupes by SKU (last row for a given SKU wins) — rejected rows are never candidates for dedup, only rows that individually pass. */
    validateAndDedupe(rows, context) {
        const creates = new Map();
        const rejected = [];
        for (const row of rows) {
            const result = this.validateRow(row, context);
            if ('reason' in result) {
                rejected.push({ rowNumber: row.rowNumber, sku: result.sku, reason: result.reason });
            }
            else {
                creates.set(result.sku, result); // Map assignment: a later row for the same SKU overwrites the earlier one.
            }
        }
        return { creates, rejected };
    }
    validateRow(row, context) {
        const cell = (header) => row.cells[header];
        const text = (header) => String(cell(header) ?? '').trim();
        const sku = text('sku');
        const name = text('name');
        const workstreamCode = text('workstream_code');
        const categoryName = text('category_name');
        const missing = [
            !sku && 'sku',
            !name && 'name',
            !workstreamCode && 'workstream_code',
            !categoryName && 'category_name',
            (0, strict_number_1.isBlankCell)(cell('selling_price')) && 'selling_price',
        ].filter((v) => Boolean(v));
        if (missing.length) {
            return { sku: sku || undefined, reason: `Row ${row.rowNumber}: missing required field(s): ${missing.join(', ')}` };
        }
        const sellingPrice = (0, strict_number_1.parseStrictNumber)(cell('selling_price'));
        if (sellingPrice === null) {
            return { sku, reason: `Row ${row.rowNumber}: selling_price ("${cell('selling_price')}") is not a valid number` };
        }
        if (sellingPrice <= 0) {
            return { sku, reason: `Row ${row.rowNumber}: selling_price must be greater than 0` };
        }
        let costPrice;
        if (!(0, strict_number_1.isBlankCell)(cell('cost_price'))) {
            const parsed = (0, strict_number_1.parseStrictNumber)(cell('cost_price'));
            if (parsed === null)
                return { sku, reason: `Row ${row.rowNumber}: cost_price ("${cell('cost_price')}") is not a valid number` };
            costPrice = parsed;
        }
        let minStockLevel = 0;
        if (!(0, strict_number_1.isBlankCell)(cell('min_stock_level'))) {
            const parsed = (0, strict_number_1.parseStrictNumber)(cell('min_stock_level'));
            if (parsed === null)
                return { sku, reason: `Row ${row.rowNumber}: min_stock_level ("${cell('min_stock_level')}") is not a valid number` };
            minStockLevel = parsed;
        }
        const workstream = context.workstreamsByCode.get(workstreamCode);
        if (!workstream) {
            return { sku, reason: `Row ${row.rowNumber}: workstream_code "${workstreamCode}" does not exist or is not active` };
        }
        if (workstream === '__AMBIGUOUS__') {
            return { sku, reason: `Row ${row.rowNumber}: workstream_code "${workstreamCode}" matches more than one active warehouse — ambiguous, cannot import` };
        }
        if (context.scopedWorkstreamIds && !context.scopedWorkstreamIds.has(workstream.id)) {
            return {
                sku,
                reason: `Row ${row.rowNumber}: workstream_code "${workstreamCode}" is outside the workstream(s) you're assigned to manage`,
            };
        }
        const candidateCategories = (context.categoriesByWorkstream.get(workstream.id) ?? []).filter((c) => c.name === categoryName);
        if (candidateCategories.length === 0) {
            return {
                sku,
                reason: `Row ${row.rowNumber}: category_name "${categoryName}" does not exist in workstream "${workstream.name}" (${workstreamCode})`,
            };
        }
        if (candidateCategories.length > 1) {
            return {
                sku,
                reason: `Row ${row.rowNumber}: category_name "${categoryName}" matches ${candidateCategories.length} categories in workstream "${workstream.name}" — ambiguous, cannot import`,
            };
        }
        const category = candidateCategories[0];
        const attributes = [];
        for (const [header, attributeType] of context.attributeTypesByHeader) {
            if (FIXED_HEADERS.has(header))
                continue; // never happens (attribute headers never collide with fixed ones) but keeps intent explicit
            const raw = cell(header);
            if ((0, strict_number_1.isBlankCell)(raw))
                continue; // omitted from this row's attribute set entirely — see the update path's full-replace note
            if (attributeType.dataType === 'NUMBER') {
                const parsed = (0, strict_number_1.parseStrictNumber)(raw);
                if (parsed === null) {
                    return { sku, reason: `Row ${row.rowNumber}: attribute "${attributeType.name}" ("${raw}") is not a valid number` };
                }
                attributes.push({ attributeTypeId: attributeType.id, name: attributeType.name, value: String(parsed) });
            }
            else {
                attributes.push({ attributeTypeId: attributeType.id, name: attributeType.name, value: text(header) });
            }
        }
        // Columns in the file that don't match any active attribute type header
        // are ignored, not an error — handled implicitly: we only ever read
        // headers we recognise (context.attributeTypesByHeader), never iterate
        // row.cells directly, so an unknown column is simply never looked at.
        return {
            rowNumber: row.rowNumber,
            sku,
            name,
            description: text('description') || undefined,
            workstreamId: workstream.id,
            workstreamCode: workstream.code,
            workstreamName: workstream.name,
            categoryId: category.id,
            categoryName: category.name,
            sellingPrice,
            costPrice,
            uom: text('uom') || 'EACH',
            minStockLevel,
            attributes,
        };
    }
    computeChanges(existing, row) {
        const changes = [];
        const push = (field, oldValue, newValue) => {
            if (oldValue !== newValue)
                changes.push({ field, oldValue, newValue });
        };
        push('name', existing.name, row.name);
        push('description', existing.description ?? '', row.description ?? '');
        push('category', `${existing.categoryName} (${existing.workstreamName})`, `${row.categoryName} (${row.workstreamName})`);
        push('sellingPrice', existing.sellingPrice, row.sellingPrice);
        push('costPrice', existing.costPrice, row.costPrice ?? null);
        push('uom', existing.uom, row.uom);
        push('minStockLevel', existing.minStockLevel, row.minStockLevel);
        const existingByType = new Map(existing.attributes.map((a) => [a.attributeTypeId, a]));
        const rowByType = new Map(row.attributes.map((a) => [a.attributeTypeId, a]));
        const allTypeIds = new Set([...existingByType.keys(), ...rowByType.keys()]);
        for (const typeId of allTypeIds) {
            const before = existingByType.get(typeId);
            const after = rowByType.get(typeId);
            const label = after?.name ?? before?.name ?? typeId;
            push(`attribute:${label}`, before?.value ?? null, after?.value ?? null);
        }
        return changes;
    }
}
exports.ProductImportService = ProductImportService;
