/// Mirrors the backend's `InventoryUnitStatus` enum — one physical item's
/// current state (see `inventory_units` in warehouse-node/db/schema.sql).
enum InventoryUnitStatus {
  pending,
  onHand,
  reserved,
  damaged,
  lost,
  expired,
  issued;

  static InventoryUnitStatus fromJson(String value) => switch (value) {
    'PENDING' => InventoryUnitStatus.pending,
    'ON_HAND' => InventoryUnitStatus.onHand,
    'RESERVED' => InventoryUnitStatus.reserved,
    'DAMAGED' => InventoryUnitStatus.damaged,
    'LOST' => InventoryUnitStatus.lost,
    'EXPIRED' => InventoryUnitStatus.expired,
    'ISSUED' => InventoryUnitStatus.issued,
    _ => throw ArgumentError('Unknown inventory unit status: $value'),
  };

  String toJson() => switch (this) {
    InventoryUnitStatus.pending => 'PENDING',
    InventoryUnitStatus.onHand => 'ON_HAND',
    InventoryUnitStatus.reserved => 'RESERVED',
    InventoryUnitStatus.damaged => 'DAMAGED',
    InventoryUnitStatus.lost => 'LOST',
    InventoryUnitStatus.expired => 'EXPIRED',
    InventoryUnitStatus.issued => 'ISSUED',
  };

  String get label => switch (this) {
    InventoryUnitStatus.pending => 'Pending (label printed, not yet received)',
    InventoryUnitStatus.onHand => 'On hand',
    InventoryUnitStatus.reserved => 'Reserved',
    InventoryUnitStatus.damaged => 'Damaged',
    InventoryUnitStatus.lost => 'Lost',
    InventoryUnitStatus.expired => 'Expired',
    InventoryUnitStatus.issued => 'Issued (dispatched)',
  };

  /// Short form for a tag/chip — unlike [label], no parenthetical.
  String get shortLabel => switch (this) {
    InventoryUnitStatus.pending => 'Pending',
    InventoryUnitStatus.onHand => 'On hand',
    InventoryUnitStatus.reserved => 'Reserved',
    InventoryUnitStatus.damaged => 'Damaged',
    InventoryUnitStatus.lost => 'Lost',
    InventoryUnitStatus.expired => 'Expired',
    InventoryUnitStatus.issued => 'Issued',
  };
}

enum InventoryUnitSource {
  generated,
  supplier;

  static InventoryUnitSource fromJson(String value) => switch (value) {
    'GENERATED' => InventoryUnitSource.generated,
    'SUPPLIER' => InventoryUnitSource.supplier,
    _ => throw ArgumentError('Unknown inventory unit source: $value'),
  };

  String get label => switch (this) {
    InventoryUnitSource.generated => 'Our label',
    InventoryUnitSource.supplier => 'Supplier barcode',
  };
}

/// The `{id, name, code, warehouseId}` the backend embeds on a unit for its
/// current location — null while PENDING (printed but not yet received) or
/// again once ISSUED (dispatched, no longer anywhere in the warehouse).
class InventoryUnitLocationRef {
  const InventoryUnitLocationRef({required this.id, required this.name, required this.code, required this.warehouseId});

  final String id;
  final String name;
  final String code;
  final String warehouseId;

  factory InventoryUnitLocationRef.fromJson(Map<String, dynamic> json) => InventoryUnitLocationRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    warehouseId: json['warehouseId'] as String,
  );
}

/// One physical item of a SERIAL-tracked product — mirrors one row of
/// `GET /inventory/units` (see `inventory_units` in db/schema.sql).
class InventoryUnit {
  const InventoryUnit({
    required this.id,
    required this.productId,
    required this.unitCode,
    required this.source,
    required this.status,
    this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String unitCode;
  final InventoryUnitSource source;
  final InventoryUnitStatus status;
  final InventoryUnitLocationRef? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory InventoryUnit.fromJson(Map<String, dynamic> json) => InventoryUnit(
    id: json['id'] as String,
    productId: json['productId'] as String,
    unitCode: json['unitCode'] as String,
    source: InventoryUnitSource.fromJson(json['source'] as String),
    status: InventoryUnitStatus.fromJson(json['status'] as String),
    location: json['location'] == null ? null : InventoryUnitLocationRef.fromJson(json['location'] as Map<String, dynamic>),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// The paginated envelope `InventoryService.findUnits` returns —
/// `{data, page, pageSize, total, totalPages}`.
class InventoryUnitsPage {
  const InventoryUnitsPage({required this.data, required this.page, required this.pageSize, required this.total, required this.totalPages});

  final List<InventoryUnit> data;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  factory InventoryUnitsPage.fromJson(Map<String, dynamic> json) => InventoryUnitsPage(
    data: (json['data'] as List<dynamic>).map((e) => InventoryUnit.fromJson(e as Map<String, dynamic>)).toList(),
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
    total: json['total'] as int,
    totalPages: json['totalPages'] as int,
  );
}
