import '../../../shared/json_utils.dart';

/// Mirrors the backend's `StockCountStatus` enum (`warehouse/prisma/schema.prisma`).
/// Only two states — there is no CANCELLED/VOID state on the real API.
enum StockCountStatus { open, submitted }

StockCountStatus stockCountStatusFromJson(String value) => switch (value) {
  'OPEN' => StockCountStatus.open,
  'SUBMITTED' => StockCountStatus.submitted,
  _ => throw ArgumentError('Unknown stock count status: $value'),
};

extension StockCountStatusX on StockCountStatus {
  String get apiValue => switch (this) {
    StockCountStatus.open => 'OPEN',
    StockCountStatus.submitted => 'SUBMITTED',
  };

  String get label => switch (this) {
    StockCountStatus.open => 'Open',
    StockCountStatus.submitted => 'Submitted',
  };
}

/// The `{id, name, code, warehouseId}` the backend embeds on a count for its
/// location (`StockCountsService`'s `COUNT_INCLUDE`) — same flat shape as
/// `InventoryBalanceLocationRef`, no ancestor chain.
class StockCountLocationRef {
  const StockCountLocationRef({
    required this.id,
    required this.name,
    required this.code,
    required this.warehouseId,
  });

  final String id;
  final String name;
  final String code;
  final String warehouseId;

  factory StockCountLocationRef.fromJson(Map<String, dynamic> json) => StockCountLocationRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    warehouseId: json['warehouseId'] as String,
  );
}

class StockCountUserRef {
  const StockCountUserRef({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  factory StockCountUserRef.fromJson(Map<String, dynamic> json) => StockCountUserRef(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    email: json['email'] as String,
  );
}

class StockCountItemProductRef {
  const StockCountItemProductRef({required this.id, required this.sku, required this.name});

  final String id;
  final String sku;
  final String name;

  factory StockCountItemProductRef.fromJson(Map<String, dynamic> json) => StockCountItemProductRef(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
  );
}

/// One product's expected-vs-counted line within a count. `countedQty`/
/// `difference` are null until the count is submitted (`StockCountsService.
/// submit` fills both in the same transaction). Decimal columns arrive as
/// JSON strings — `numFromJson` parses either representation.
class StockCountItem {
  const StockCountItem({
    required this.id,
    required this.stockCountId,
    required this.productId,
    required this.locationId,
    required this.expectedQty,
    this.countedQty,
    this.difference,
    required this.product,
  });

  final String id;
  final String stockCountId;
  final String productId;
  final String locationId;
  final double expectedQty;
  final double? countedQty;
  final double? difference;
  final StockCountItemProductRef product;

  factory StockCountItem.fromJson(Map<String, dynamic> json) => StockCountItem(
    id: json['id'] as String,
    stockCountId: json['stockCountId'] as String,
    productId: json['productId'] as String,
    locationId: json['locationId'] as String,
    expectedQty: numFromJson(json['expectedQty']),
    countedQty: json['countedQty'] == null ? null : numFromJson(json['countedQty']),
    difference: json['difference'] == null ? null : numFromJson(json['difference']),
    product: StockCountItemProductRef.fromJson(json['product'] as Map<String, dynamic>),
  );
}

/// Mirrors `GET/POST /inventory/counts` and `PATCH /inventory/counts/:id`
/// (`StockCountsService` on the backend). Scoped to ONE leaf location per
/// count (rule 5 — `assertLeaf` on `create`). Starting a count only reads
/// `inventory_balances` to snapshot `expectedQty`; it never writes to
/// `inventory_balances`/`inventory_transactions` itself — submitting turns
/// nonzero variances into PENDING `StockAdjustment`s via the exact same path
/// as a manually-requested one (see `stock_adjustments/domain`).
class StockCount {
  const StockCount({
    required this.id,
    required this.warehouseId,
    required this.locationId,
    required this.status,
    required this.startedBy,
    required this.startedAt,
    this.submittedAt,
    required this.location,
    required this.startedByUser,
    required this.items,
    this.createdAdjustmentIds,
  });

  final String id;
  final String warehouseId;
  final String locationId;
  final StockCountStatus status;
  final String startedBy;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final StockCountLocationRef location;
  final StockCountUserRef startedByUser;
  final List<StockCountItem> items;

  /// Only present on the response to `PATCH /inventory/counts/:id` (the
  /// submit call) — `StockCountsService.submit` spreads it onto the fresh
  /// `getExisting()` result. A later `GET` of the same count omits it; the
  /// count's own items (with nonzero `difference`) are the durable record of
  /// which adjustments were created, matched by `StockAdjustment.reference
  /// == count.id`.
  final List<String>? createdAdjustmentIds;

  factory StockCount.fromJson(Map<String, dynamic> json) => StockCount(
    id: json['id'] as String,
    warehouseId: json['warehouseId'] as String,
    locationId: json['locationId'] as String,
    status: stockCountStatusFromJson(json['status'] as String),
    startedBy: json['startedBy'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    submittedAt: json['submittedAt'] == null ? null : DateTime.parse(json['submittedAt'] as String),
    location: StockCountLocationRef.fromJson(json['location'] as Map<String, dynamic>),
    startedByUser: StockCountUserRef.fromJson(json['startedByUser'] as Map<String, dynamic>),
    items: (json['items'] as List<dynamic>)
        .map((e) => StockCountItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAdjustmentIds: (json['createdAdjustmentIds'] as List<dynamic>?)?.cast<String>(),
  );
}
