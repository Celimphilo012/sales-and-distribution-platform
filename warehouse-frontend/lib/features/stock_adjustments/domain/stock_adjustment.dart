import '../../../shared/json_utils.dart';

/// Mirrors the backend's `AdjustmentBucket` enum — which `inventory_balances`
/// bucket this adjustment corrects (rule 4: on_hand/reserved/damaged/lost/
/// expired are distinct, never overwritten directly).
enum AdjustmentBucket { onHand, reserved, damaged, lost, expired }

AdjustmentBucket adjustmentBucketFromJson(String value) => switch (value) {
  'ON_HAND' => AdjustmentBucket.onHand,
  'RESERVED' => AdjustmentBucket.reserved,
  'DAMAGED' => AdjustmentBucket.damaged,
  'LOST' => AdjustmentBucket.lost,
  'EXPIRED' => AdjustmentBucket.expired,
  _ => throw ArgumentError('Unknown adjustment bucket: $value'),
};

extension AdjustmentBucketX on AdjustmentBucket {
  String get apiValue => switch (this) {
    AdjustmentBucket.onHand => 'ON_HAND',
    AdjustmentBucket.reserved => 'RESERVED',
    AdjustmentBucket.damaged => 'DAMAGED',
    AdjustmentBucket.lost => 'LOST',
    AdjustmentBucket.expired => 'EXPIRED',
  };

  String get label => switch (this) {
    AdjustmentBucket.onHand => 'On hand',
    AdjustmentBucket.reserved => 'Reserved',
    AdjustmentBucket.damaged => 'Damaged',
    AdjustmentBucket.lost => 'Lost',
    AdjustmentBucket.expired => 'Expired',
  };
}

enum AdjustmentDirection { increase, decrease }

AdjustmentDirection adjustmentDirectionFromJson(String value) => switch (value) {
  'INCREASE' => AdjustmentDirection.increase,
  'DECREASE' => AdjustmentDirection.decrease,
  _ => throw ArgumentError('Unknown adjustment direction: $value'),
};

extension AdjustmentDirectionX on AdjustmentDirection {
  String get apiValue => this == AdjustmentDirection.increase ? 'INCREASE' : 'DECREASE';
  String get label => this == AdjustmentDirection.increase ? 'Increase' : 'Decrease';
}

/// PENDING → (APPROVED | REJECTED). Approval is the only thing that ever
/// moves stock (`StockAdjustmentsService.approve` calls
/// `InventoryService.applyTransaction()`); request and reject never touch
/// `inventory_balances`.
enum AdjustmentStatus { pending, approved, rejected }

AdjustmentStatus adjustmentStatusFromJson(String value) => switch (value) {
  'PENDING' => AdjustmentStatus.pending,
  'APPROVED' => AdjustmentStatus.approved,
  'REJECTED' => AdjustmentStatus.rejected,
  _ => throw ArgumentError('Unknown adjustment status: $value'),
};

extension AdjustmentStatusX on AdjustmentStatus {
  String get apiValue => switch (this) {
    AdjustmentStatus.pending => 'PENDING',
    AdjustmentStatus.approved => 'APPROVED',
    AdjustmentStatus.rejected => 'REJECTED',
  };

  String get label => switch (this) {
    AdjustmentStatus.pending => 'Pending',
    AdjustmentStatus.approved => 'Approved',
    AdjustmentStatus.rejected => 'Rejected',
  };
}

class AdjustmentProductRef {
  const AdjustmentProductRef({required this.id, required this.sku, required this.name});

  final String id;
  final String sku;
  final String name;

  factory AdjustmentProductRef.fromJson(Map<String, dynamic> json) => AdjustmentProductRef(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
  );
}

class AdjustmentLocationRef {
  const AdjustmentLocationRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory AdjustmentLocationRef.fromJson(Map<String, dynamic> json) => AdjustmentLocationRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
  );
}

class AdjustmentUserRef {
  const AdjustmentUserRef({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  factory AdjustmentUserRef.fromJson(Map<String, dynamic> json) => AdjustmentUserRef(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    email: json['email'] as String,
  );
}

/// Mirrors `GET/POST /inventory/adjustments` and `POST /inventory/
/// adjustments/:id/{approve,reject}` (`StockAdjustmentsService`). §F's
/// two-step approval: a request (`inventory.adjust.request`) never moves
/// stock; only `approve` (`inventory.adjust.approve`) does, and the backend
/// enforces separation of duties — `reviewedBy == requestedBy` is rejected
/// with a 403 regardless of what permissions the reviewer holds. `reference`
/// links an adjustment created by a stock count back to that count's id
/// (`StockCountsService.submit` sets it to the count's id; a manually
/// requested adjustment leaves it null unless the requester supplies one).
class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.productId,
    required this.locationId,
    required this.bucket,
    required this.delta,
    required this.direction,
    required this.reason,
    this.reference,
    required this.status,
    required this.requestedBy,
    required this.requestedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    required this.product,
    required this.location,
    required this.requestedByUser,
    this.reviewedByUser,
  });

  final String id;
  final String productId;
  final String locationId;
  final AdjustmentBucket bucket;
  final double delta;
  final AdjustmentDirection direction;
  final String reason;
  final String? reference;
  final AdjustmentStatus status;
  final String requestedBy;
  final DateTime requestedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final AdjustmentProductRef product;
  final AdjustmentLocationRef location;
  final AdjustmentUserRef requestedByUser;
  final AdjustmentUserRef? reviewedByUser;

  factory StockAdjustment.fromJson(Map<String, dynamic> json) => StockAdjustment(
    id: json['id'] as String,
    productId: json['productId'] as String,
    locationId: json['locationId'] as String,
    bucket: adjustmentBucketFromJson(json['bucket'] as String),
    delta: numFromJson(json['delta']),
    direction: adjustmentDirectionFromJson(json['direction'] as String),
    reason: json['reason'] as String,
    reference: json['reference'] as String?,
    status: adjustmentStatusFromJson(json['status'] as String),
    requestedBy: json['requestedBy'] as String,
    requestedAt: DateTime.parse(json['requestedAt'] as String),
    reviewedBy: json['reviewedBy'] as String?,
    reviewedAt: json['reviewedAt'] == null ? null : DateTime.parse(json['reviewedAt'] as String),
    reviewNote: json['reviewNote'] as String?,
    product: AdjustmentProductRef.fromJson(json['product'] as Map<String, dynamic>),
    location: AdjustmentLocationRef.fromJson(json['location'] as Map<String, dynamic>),
    requestedByUser: AdjustmentUserRef.fromJson(json['requestedByUser'] as Map<String, dynamic>),
    reviewedByUser: json['reviewedByUser'] == null
        ? null
        : AdjustmentUserRef.fromJson(json['reviewedByUser'] as Map<String, dynamic>),
  );
}
