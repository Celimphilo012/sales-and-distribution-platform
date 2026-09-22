/// Mirrors the warehouse backend's `product-import.types.ts` response
/// shapes exactly — this feature has no model of its own to diverge from,
/// it's a straight read of what `/products/import/preview` and
/// `/products/import/confirm` return.
library;

class ImportAttributeValue {
  const ImportAttributeValue({required this.attributeTypeId, required this.name, required this.value});

  final String attributeTypeId;
  final String name;
  final String value;

  factory ImportAttributeValue.fromJson(Map<String, dynamic> json) => ImportAttributeValue(
    attributeTypeId: json['attributeTypeId'] as String,
    name: json['name'] as String,
    value: json['value'] as String,
  );
}

/// Everything needed to create the product, plus display fields — shared by
/// [ImportCreateRow] and [ImportUpdateRow] (which extends it on the backend;
/// Dart has no interface-extends-with-extra-fields shortcut for JSON models,
/// so [ImportUpdateRow] composes one of these rather than inheriting).
class ImportCreateRow {
  const ImportCreateRow({
    required this.rowNumber,
    required this.sku,
    required this.name,
    this.description,
    required this.workstreamId,
    required this.workstreamCode,
    required this.workstreamName,
    required this.categoryId,
    required this.categoryName,
    required this.sellingPrice,
    this.costPrice,
    required this.uom,
    required this.minStockLevel,
    required this.attributes,
  });

  final int rowNumber;
  final String sku;
  final String name;
  final String? description;
  final String workstreamId;
  final String workstreamCode;
  final String workstreamName;
  final String categoryId;
  final String categoryName;
  final double sellingPrice;
  final double? costPrice;
  final String uom;
  final double minStockLevel;
  final List<ImportAttributeValue> attributes;

  factory ImportCreateRow.fromJson(Map<String, dynamic> json) => ImportCreateRow(
    rowNumber: json['rowNumber'] as int,
    sku: json['sku'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    workstreamId: json['workstreamId'] as String,
    workstreamCode: json['workstreamCode'] as String,
    workstreamName: json['workstreamName'] as String,
    categoryId: json['categoryId'] as String,
    categoryName: json['categoryName'] as String,
    sellingPrice: (json['sellingPrice'] as num).toDouble(),
    costPrice: (json['costPrice'] as num?)?.toDouble(),
    uom: json['uom'] as String,
    minStockLevel: (json['minStockLevel'] as num).toDouble(),
    attributes: (json['attributes'] as List<dynamic>? ?? const [])
        .map((e) => ImportAttributeValue.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ImportChange {
  const ImportChange({required this.field, required this.oldValue, required this.newValue});

  final String field;
  final Object? oldValue;
  final Object? newValue;

  factory ImportChange.fromJson(Map<String, dynamic> json) =>
      ImportChange(field: json['field'] as String, oldValue: json['oldValue'], newValue: json['newValue']);
}

class ImportUpdateRow {
  const ImportUpdateRow({required this.row, required this.existingProductId, required this.changes});

  final ImportCreateRow row;
  final String existingProductId;
  final List<ImportChange> changes;

  factory ImportUpdateRow.fromJson(Map<String, dynamic> json) => ImportUpdateRow(
    row: ImportCreateRow.fromJson(json),
    existingProductId: json['existingProductId'] as String,
    changes: (json['changes'] as List<dynamic>? ?? const [])
        .map((e) => ImportChange.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ImportRejectedRow {
  const ImportRejectedRow({required this.rowNumber, this.sku, required this.reason});

  final int rowNumber;
  final String? sku;
  final String reason;

  factory ImportRejectedRow.fromJson(Map<String, dynamic> json) => ImportRejectedRow(
    rowNumber: json['rowNumber'] as int,
    sku: json['sku'] as String?,
    reason: json['reason'] as String,
  );
}

class ImportPreviewSummary {
  const ImportPreviewSummary({
    required this.createCount,
    required this.updateCount,
    required this.rejectCount,
    required this.totalRows,
  });

  final int createCount;
  final int updateCount;
  final int rejectCount;
  final int totalRows;

  factory ImportPreviewSummary.fromJson(Map<String, dynamic> json) => ImportPreviewSummary(
    createCount: json['createCount'] as int,
    updateCount: json['updateCount'] as int,
    rejectCount: json['rejectCount'] as int,
    totalRows: json['totalRows'] as int,
  );
}

class ImportPreviewResult {
  const ImportPreviewResult({
    required this.importSessionId,
    required this.fileName,
    required this.toCreate,
    required this.toUpdate,
    required this.rejected,
    required this.summary,
  });

  final String importSessionId;
  final String fileName;
  final List<ImportCreateRow> toCreate;
  final List<ImportUpdateRow> toUpdate;
  final List<ImportRejectedRow> rejected;
  final ImportPreviewSummary summary;

  factory ImportPreviewResult.fromJson(Map<String, dynamic> json) => ImportPreviewResult(
    importSessionId: json['importSessionId'] as String,
    fileName: json['fileName'] as String,
    toCreate: (json['toCreate'] as List<dynamic>? ?? const [])
        .map((e) => ImportCreateRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    toUpdate: (json['toUpdate'] as List<dynamic>? ?? const [])
        .map((e) => ImportUpdateRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    rejected: (json['rejected'] as List<dynamic>? ?? const [])
        .map((e) => ImportRejectedRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    summary: ImportPreviewSummary.fromJson(json['summary'] as Map<String, dynamic>),
  );
}

class ImportFailedRow {
  const ImportFailedRow({required this.sku, required this.reason});

  final String sku;
  final String reason;

  factory ImportFailedRow.fromJson(Map<String, dynamic> json) =>
      ImportFailedRow(sku: json['sku'] as String, reason: json['reason'] as String);
}

class ImportConfirmResult {
  const ImportConfirmResult({required this.created, required this.updated, required this.failed});

  final int created;
  final int updated;
  final List<ImportFailedRow> failed;

  factory ImportConfirmResult.fromJson(Map<String, dynamic> json) => ImportConfirmResult(
    created: json['created'] as int,
    updated: json['updated'] as int,
    failed: (json['failed'] as List<dynamic>? ?? const [])
        .map((e) => ImportFailedRow.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
