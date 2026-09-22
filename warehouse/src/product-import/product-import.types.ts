// Shared response/session shapes for the product-import feature. Plain
// interfaces (not class-validator DTOs) since these only ever flow
// service -> controller -> JSON response, the same convention the rest of
// the warehouse backend uses for read shapes (e.g. ProductsService just
// returns Prisma results — no response DTOs anywhere in this codebase).

export interface ImportAttributeValue {
  attributeTypeId: string;
  name: string;
  value: string;
}

/** Everything needed to actually CREATE the product, plus display fields for the preview table. */
export interface ImportCreateRow {
  rowNumber: number;
  sku: string;
  name: string;
  description?: string;
  workstreamId: string;
  workstreamCode: string;
  workstreamName: string;
  categoryId: string;
  categoryName: string;
  sellingPrice: number;
  costPrice?: number;
  uom: string;
  minStockLevel: number;
  attributes: ImportAttributeValue[];
}

export interface ImportChange {
  field: string;
  oldValue: unknown;
  newValue: unknown;
}

export interface ImportUpdateRow extends ImportCreateRow {
  existingProductId: string;
  changes: ImportChange[];
}

export interface ImportRejectedRow {
  rowNumber: number;
  sku?: string;
  reason: string;
}

export interface ImportPreviewSummary {
  createCount: number;
  updateCount: number;
  rejectCount: number;
  totalRows: number;
}

export interface ImportPreviewResult {
  importSessionId: string;
  fileName: string;
  toCreate: ImportCreateRow[];
  toUpdate: ImportUpdateRow[];
  rejected: ImportRejectedRow[];
  summary: ImportPreviewSummary;
}

export interface ImportConfirmResult {
  created: number;
  updated: number;
  failed: { sku: string; reason: string }[];
}
