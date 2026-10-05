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

/// The `sale` block a product carries when it's currently on an ACTIVE sale campaign
/// (warehouse-node's `attachActiveSale`) — terms only; `effectivePrice` is set for an
/// ALL_CUSTOMERS campaign, null for RESTRICTED (the warehouse never resolves a customer-specific
/// price — see orders.js `buildLineInputs`, which is what actually prices the order line on save).
/// Display/estimate only here — same "server snapshots the real price" principle as the rest of
/// this picker.
class WarehouseProductSale {
  const WarehouseProductSale({
    required this.campaignId,
    required this.campaignName,
    required this.discountType,
    required this.discountValue,
    required this.minQuantity,
    required this.eligibility,
    this.effectivePrice,
  });

  final String campaignId;
  final String campaignName;
  final String discountType; // PERCENT | FIXED_AMOUNT | FIXED_PRICE
  final double discountValue;
  final double minQuantity;
  final String eligibility; // ALL_CUSTOMERS | RESTRICTED
  final double? effectivePrice;

  bool get isRestricted => eligibility == 'RESTRICTED';

  /// Same math as warehouse-node's `discountedPrice` / ordering-backend's `discountedPrice` —
  /// deliberately duplicated a third time, no shared code across systems or apps.
  double previewPrice(double sellingPrice) {
    final raw = switch (discountType) {
      'PERCENT' => sellingPrice * (1 - discountValue / 100),
      'FIXED_AMOUNT' => sellingPrice - discountValue,
      _ => discountValue, // FIXED_PRICE
    };
    return raw < 0 ? 0 : (raw * 100).round() / 100;
  }

  factory WarehouseProductSale.fromJson(Map<String, dynamic> json) => WarehouseProductSale(
    campaignId: json['campaignId'] as String,
    campaignName: json['campaignName'] as String,
    discountType: json['discountType'] as String,
    discountValue: _num(json['discountValue']),
    minQuantity: _num(json['minQuantity']),
    eligibility: json['eligibility'] as String,
    effectivePrice: json['effectivePrice'] == null ? null : _num(json['effectivePrice']),
  );
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
    this.sale,
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
  final WarehouseProductSale? sale;

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
    sale: json['sale'] == null ? null : WarehouseProductSale.fromJson(json['sale'] as Map<String, dynamic>),
  );
}

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
