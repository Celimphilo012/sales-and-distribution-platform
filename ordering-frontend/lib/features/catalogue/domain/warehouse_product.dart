/// Mirrors `GET /catalogue`'s (STEP R3a — the new frontend-facing relay,
/// see `CatalogueController` on `/backend`) product shape, which is
/// whatever the warehouse's own external `GET /api/v1/catalogue` returns —
/// richer than `/backend`'s internal `WarehouseProduct` TypeScript
/// interface declares (that type predates workstream/attributes; the JSON
/// itself already carries them since `WarehouseApiClient` doesn't validate,
/// just relays). This app is READ-ONLY against the catalogue — it exists
/// here purely to pick a product + see its price while building an order
/// line; product/category/attribute MANAGEMENT stays in
/// `/warehouse-frontend`.
class WarehouseProductWorkstreamRef {
  const WarehouseProductWorkstreamRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory WarehouseProductWorkstreamRef.fromJson(Map<String, dynamic> json) => WarehouseProductWorkstreamRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
  );
}

class WarehouseProductCategoryRef {
  const WarehouseProductCategoryRef({required this.id, required this.name, this.workstream});

  final String id;
  final String name;
  final WarehouseProductWorkstreamRef? workstream;

  factory WarehouseProductCategoryRef.fromJson(Map<String, dynamic> json) => WarehouseProductCategoryRef(
    id: json['id'] as String,
    name: json['name'] as String,
    workstream: json['workstream'] == null
        ? null
        : WarehouseProductWorkstreamRef.fromJson(json['workstream'] as Map<String, dynamic>),
  );
}

/// One `{attribute type, value}` pair — descriptive only (colour, size,
/// weight, ...), never a variant; shown as-is, display-only here.
class WarehouseProductAttribute {
  const WarehouseProductAttribute({required this.name, required this.value, this.unit});

  final String name;
  final String value;
  final String? unit;

  factory WarehouseProductAttribute.fromJson(Map<String, dynamic> json) {
    final attributeType = json['attributeType'] as Map<String, dynamic>?;
    return WarehouseProductAttribute(
      name: attributeType?['name'] as String? ?? '—',
      value: json['value'].toString(),
      unit: attributeType?['unit'] as String?,
    );
  }

  String get display => unit != null && unit!.isNotEmpty ? '$name: $value $unit' : '$name: $value';
}

class WarehouseProduct {
  const WarehouseProduct({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    required this.sellingPrice,
    required this.uom,
    required this.status,
    this.category,
    this.attributes = const [],
  });

  final String id;
  final String sku;
  final String name;
  final String? description;
  final double sellingPrice;
  final String uom;
  final String status;
  final WarehouseProductCategoryRef? category;
  final List<WarehouseProductAttribute> attributes;

  bool get isActive => status == 'ACTIVE';

  factory WarehouseProduct.fromJson(Map<String, dynamic> json) => WarehouseProduct(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    sellingPrice: _num(json['sellingPrice']),
    uom: json['uom'] as String,
    status: json['status'] as String,
    category: json['category'] == null
        ? null
        : WarehouseProductCategoryRef.fromJson(json['category'] as Map<String, dynamic>),
    attributes: (json['attributes'] as List<dynamic>? ?? const [])
        .map((e) => WarehouseProductAttribute.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
