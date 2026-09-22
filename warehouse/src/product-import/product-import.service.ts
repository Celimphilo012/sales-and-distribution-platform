import { Injectable, NotFoundException } from '@nestjs/common';
import { AttributeDataType, Prisma } from '@prisma/client';
import { ProductsService } from '../products/products.service';
import { CategoriesService } from '../categories/categories.service';
import { WorkstreamsService } from '../workstreams/workstreams.service';
import { AttributeTypesService } from '../attribute-types/attribute-types.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { readSpreadsheetRows, RawImportRow } from './parsing/spreadsheet-reader';
import { isBlankCell, parseStrictNumber } from './parsing/strict-number';
import { buildImportTemplate, TemplateAttributeColumn, TemplateExampleRow } from './template/build-import-template';
import { ProductImportSessionStore } from './product-import-session.store';
import {
  ImportAttributeValue,
  ImportChange,
  ImportConfirmResult,
  ImportCreateRow,
  ImportPreviewResult,
  ImportRejectedRow,
  ImportUpdateRow,
} from './product-import.types';

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
function attributeHeader(attributeType: { name: string; unit: string | null }): string {
  return attributeType.unit ? `${attributeType.name} (${attributeType.unit})` : attributeType.name;
}

interface ActiveWorkstream {
  id: string;
  code: string;
  name: string;
  warehouseId: string;
}

interface ActiveCategory {
  id: string;
  name: string;
  workstreamId: string;
}

interface ActiveAttributeType {
  id: string;
  name: string;
  dataType: AttributeDataType;
  header: string;
}

interface ValidationContext {
  workstreamsByCode: Map<string, ActiveWorkstream | '__AMBIGUOUS__'>;
  categoriesByWorkstream: Map<string, ActiveCategory[]>; // workstreamId -> its active categories
  attributeTypesByHeader: Map<string, ActiveAttributeType>;
  existingBySku: Map<string, ExistingProduct>;
}

interface ExistingProduct {
  id: string;
  name: string;
  description: string | null;
  categoryId: string;
  categoryName: string;
  workstreamName: string;
  sellingPrice: number;
  costPrice: number | null;
  uom: string;
  minStockLevel: number;
  attributes: { attributeTypeId: string; name: string; value: string }[];
}

@Injectable()
export class ProductImportService {
  constructor(
    private readonly productsService: ProductsService,
    private readonly categoriesService: CategoriesService,
    private readonly workstreamsService: WorkstreamsService,
    private readonly attributeTypesService: AttributeTypesService,
    private readonly warehousesService: WarehousesService,
    private readonly sessions: ProductImportSessionStore,
  ) {}

  // -----------------------------------------------------------------
  // 1. Template
  // -----------------------------------------------------------------

  async buildTemplate(): Promise<Buffer> {
    const attributeTypes = await this.attributeTypesService.findAll({ includeInactive: false });
    const attributeColumns: TemplateAttributeColumn[] = attributeTypes.map((a) => ({
      header: attributeHeader(a),
      dataType: a.dataType,
    }));

    const examples = await this.buildExampleRows(attributeTypes);
    return buildImportTemplate(attributeColumns, examples);
  }

  /**
   * Picks up to two REAL active (workstream, category) pairs to build
   * genuinely-valid example rows from — so the template is immediately
   * re-uploadable as a working demonstration, and never goes stale by
   * naming a workstream/category that doesn't exist in whatever catalogue
   * is actually live when it's downloaded.
   */
  private async buildExampleRows(
    attributeTypes: { id: string; name: string; unit: string | null; dataType: AttributeDataType }[],
  ): Promise<TemplateExampleRow[]> {
    const activeWorkstreams = await this.getActiveWorkstreams();
    const activeWorkstreamIds = new Set(activeWorkstreams.map((w) => w.id));
    const workstreamById = new Map(activeWorkstreams.map((w) => [w.id, w]));

    const allActiveCategories = await this.categoriesService.findAll({ includeInactive: false });
    const categories = allActiveCategories
      .filter((c) => activeWorkstreamIds.has(c.workstreamId))
      .sort((a, b) => a.workstreamId.localeCompare(b.workstreamId) || a.name.localeCompare(b.name))
      .slice(0, 2);
    if (categories.length === 0) return [];

    const sampleAttributeValues = (seed: number): Record<string, string> => {
      const values: Record<string, string> = {};
      for (const attributeType of attributeTypes) {
        const header = attributeHeader(attributeType);
        if (attributeType.dataType === 'NUMBER') {
          if (attributeType.name.toLowerCase() === 'weight') values[header] = seed === 0 ? '0.5' : '0.12';
        } else if (attributeType.name.toLowerCase() === 'colour') {
          values[header] = seed === 0 ? 'Blue' : 'Ivory';
        } else if (attributeType.name.toLowerCase() === 'brand') {
          values[header] = seed === 0 ? 'HomeFresh' : 'Aroma Naturals';
        }
      }
      return values;
    };

    const rows: TemplateExampleRow[] = [
      {
        sku: 'IMP-EXAMPLE-001',
        name: 'All-Purpose Cleaner Spray 500ml',
        description: 'Multi-surface cleaning spray, 500ml trigger bottle',
        workstreamCode: workstreamById.get(categories[0].workstreamId)!.code,
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
        workstreamCode: workstreamById.get(categories[1].workstreamId)!.code,
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

  async preview(file: { buffer: Buffer; originalname: string }, userId: string): Promise<ImportPreviewResult> {
    const rawRows = await readSpreadsheetRows(file.buffer, file.originalname);

    const context = await this.buildValidationContext(rawRows);
    const { creates, rejected } = this.validateAndDedupe(rawRows, context);

    const toCreate: ImportCreateRow[] = [];
    const toUpdate: ImportUpdateRow[] = [];
    for (const row of creates.values()) {
      const existing = context.existingBySku.get(row.sku);
      if (existing) {
        toUpdate.push({ ...row, existingProductId: existing.id, changes: this.computeChanges(existing, row) });
      } else {
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

  async confirm(importSessionId: string, userId: string): Promise<ImportConfirmResult & { fileName: string }> {
    const session = this.sessions.take(importSessionId);
    if (!session) {
      throw new NotFoundException('This import session has expired or was already confirmed — upload the file again for a fresh preview.');
    }
    // Single-use regardless of outcome below — a stale preview should never
    // be replayable, and a failed confirm should be retried via a fresh
    // upload/preview so it re-validates against current data.
    this.sessions.discard(importSessionId);

    const failed: { sku: string; reason: string }[] = [];
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
        });
        created++;
      } catch (error) {
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
        });
        updated++;
      } catch (error) {
        failed.push({ sku: row.sku, reason: this.describeWriteError(error) });
      }
    }

    // Who imported is already on the audit_logs row via request.user;
    // created/updated/failed counts + the file name are attached by the
    // controller (see ProductImportController.confirm) so they land in the
    // same row's newValue instead of a second write.
    return { created, updated, failed, fileName: session.fileName };
  }

  private describeWriteError(error: unknown): string {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return 'A product with this SKU already exists';
    }
    if (error instanceof NotFoundException) {
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
  private async revalidateStillActive(row: ImportCreateRow): Promise<string | null> {
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
  private async getActiveWorkstreams(): Promise<ActiveWorkstream[]> {
    const [workstreams, warehouses] = await Promise.all([
      this.workstreamsService.findAll({ includeInactive: false }),
      this.warehousesService.findAll({ includeInactive: false }),
    ]);
    const activeWarehouseIds = new Set(warehouses.map((w) => w.id));
    return workstreams
      .filter((w) => activeWarehouseIds.has(w.warehouseId))
      .map((w) => ({ id: w.id, code: w.code, name: w.name, warehouseId: w.warehouseId }));
  }

  private async buildValidationContext(rows: RawImportRow[]): Promise<ValidationContext> {
    const [activeWorkstreams, categories, attributeTypes] = await Promise.all([
      this.getActiveWorkstreams(),
      this.categoriesService.findAll({ includeInactive: false }),
      this.attributeTypesService.findAll({ includeInactive: false }),
    ]);

    const workstreamsByCode = new Map<string, ActiveWorkstream | '__AMBIGUOUS__'>();
    for (const w of activeWorkstreams) {
      // Codes are only unique PER WAREHOUSE (schema: @@unique([warehouseId,
      // code])), not globally — with more than one active warehouse two
      // could collide. Currently there's exactly one active warehouse, so
      // this never fires in practice, but a collision is reported per-row
      // rather than silently picking one.
      workstreamsByCode.set(w.code, workstreamsByCode.has(w.code) ? '__AMBIGUOUS__' : w);
    }

    const categoriesByWorkstream = new Map<string, ActiveCategory[]>();
    for (const c of categories) {
      const list = categoriesByWorkstream.get(c.workstreamId) ?? [];
      list.push({ id: c.id, name: c.name, workstreamId: c.workstreamId });
      categoriesByWorkstream.set(c.workstreamId, list);
    }

    const attributeTypesByHeader = new Map<string, ActiveAttributeType>();
    for (const a of attributeTypes) {
      attributeTypesByHeader.set(attributeHeader(a), { id: a.id, name: a.name, dataType: a.dataType, header: attributeHeader(a) });
    }

    const skusInFile = new Set<string>();
    for (const row of rows) {
      const sku = String(row.cells['sku'] ?? '').trim();
      if (sku) skusInFile.add(sku);
    }
    const existingProducts = await this.productsService.findManyBySkus([...skusInFile]);
    const existingBySku = new Map<string, ExistingProduct>();
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

    return { workstreamsByCode, categoriesByWorkstream, attributeTypesByHeader, existingBySku };
  }

  /** Validates every row, then dedupes by SKU (last row for a given SKU wins) — rejected rows are never candidates for dedup, only rows that individually pass. */
  private validateAndDedupe(
    rows: RawImportRow[],
    context: ValidationContext,
  ): { creates: Map<string, ImportCreateRow>; rejected: ImportRejectedRow[] } {
    const creates = new Map<string, ImportCreateRow>();
    const rejected: ImportRejectedRow[] = [];

    for (const row of rows) {
      const result = this.validateRow(row, context);
      if ('reason' in result) {
        rejected.push({ rowNumber: row.rowNumber, sku: result.sku, reason: result.reason });
      } else {
        creates.set(result.sku, result); // Map assignment: a later row for the same SKU overwrites the earlier one.
      }
    }

    return { creates, rejected };
  }

  private validateRow(
    row: RawImportRow,
    context: ValidationContext,
  ): ImportCreateRow | { reason: string; sku?: string } {
    const cell = (header: string) => row.cells[header];
    const text = (header: string) => String(cell(header) ?? '').trim();

    const sku = text('sku');
    const name = text('name');
    const workstreamCode = text('workstream_code');
    const categoryName = text('category_name');

    const missing = [
      !sku && 'sku',
      !name && 'name',
      !workstreamCode && 'workstream_code',
      !categoryName && 'category_name',
      isBlankCell(cell('selling_price')) && 'selling_price',
    ].filter((v): v is string => Boolean(v));
    if (missing.length) {
      return { sku: sku || undefined, reason: `Row ${row.rowNumber}: missing required field(s): ${missing.join(', ')}` };
    }

    const sellingPrice = parseStrictNumber(cell('selling_price'));
    if (sellingPrice === null) {
      return { sku, reason: `Row ${row.rowNumber}: selling_price ("${cell('selling_price')}") is not a valid number` };
    }
    if (sellingPrice <= 0) {
      return { sku, reason: `Row ${row.rowNumber}: selling_price must be greater than 0` };
    }

    let costPrice: number | undefined;
    if (!isBlankCell(cell('cost_price'))) {
      const parsed = parseStrictNumber(cell('cost_price'));
      if (parsed === null) return { sku, reason: `Row ${row.rowNumber}: cost_price ("${cell('cost_price')}") is not a valid number` };
      costPrice = parsed;
    }

    let minStockLevel = 0;
    if (!isBlankCell(cell('min_stock_level'))) {
      const parsed = parseStrictNumber(cell('min_stock_level'));
      if (parsed === null) return { sku, reason: `Row ${row.rowNumber}: min_stock_level ("${cell('min_stock_level')}") is not a valid number` };
      minStockLevel = parsed;
    }

    const workstream = context.workstreamsByCode.get(workstreamCode);
    if (!workstream) {
      return { sku, reason: `Row ${row.rowNumber}: workstream_code "${workstreamCode}" does not exist or is not active` };
    }
    if (workstream === '__AMBIGUOUS__') {
      return { sku, reason: `Row ${row.rowNumber}: workstream_code "${workstreamCode}" matches more than one active warehouse — ambiguous, cannot import` };
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

    const attributes: ImportAttributeValue[] = [];
    for (const [header, attributeType] of context.attributeTypesByHeader) {
      if (FIXED_HEADERS.has(header)) continue; // never happens (attribute headers never collide with fixed ones) but keeps intent explicit
      const raw = cell(header);
      if (isBlankCell(raw)) continue; // omitted from this row's attribute set entirely — see the update path's full-replace note

      if (attributeType.dataType === 'NUMBER') {
        const parsed = parseStrictNumber(raw);
        if (parsed === null) {
          return { sku, reason: `Row ${row.rowNumber}: attribute "${attributeType.name}" ("${raw}") is not a valid number` };
        }
        attributes.push({ attributeTypeId: attributeType.id, name: attributeType.name, value: String(parsed) });
      } else {
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

  private computeChanges(existing: ExistingProduct, row: ImportCreateRow): ImportChange[] {
    const changes: ImportChange[] = [];
    const push = (field: string, oldValue: unknown, newValue: unknown) => {
      if (oldValue !== newValue) changes.push({ field, oldValue, newValue });
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
