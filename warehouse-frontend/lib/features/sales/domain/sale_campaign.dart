import '../../../shared/json_utils.dart';

/// Mirrors the backend's `SaleCampaignEligibility` enum.
enum SaleEligibility { allCustomers, restricted }

SaleEligibility saleEligibilityFromJson(String value) => switch (value) {
  'ALL_CUSTOMERS' => SaleEligibility.allCustomers,
  'RESTRICTED' => SaleEligibility.restricted,
  _ => throw ArgumentError('Unknown sale eligibility: $value'),
};

extension SaleEligibilityX on SaleEligibility {
  String get apiValue => this == SaleEligibility.allCustomers ? 'ALL_CUSTOMERS' : 'RESTRICTED';
  String get label => this == SaleEligibility.allCustomers ? 'Every customer' : 'Restricted to specific customers';
}

/// PENDING_APPROVAL -> (SCHEDULED | ACTIVE | REJECTED) -> ... -> (ENDED | CANCELLED).
/// SCHEDULED -> ACTIVE -> ENDED are flipped by the server's cron tick, never by a client request —
/// see warehouse-node/src/modules/sales/service.js.
enum SaleCampaignStatus { pendingApproval, scheduled, active, ended, rejected, cancelled }

SaleCampaignStatus saleCampaignStatusFromJson(String value) => switch (value) {
  'PENDING_APPROVAL' => SaleCampaignStatus.pendingApproval,
  'SCHEDULED' => SaleCampaignStatus.scheduled,
  'ACTIVE' => SaleCampaignStatus.active,
  'ENDED' => SaleCampaignStatus.ended,
  'REJECTED' => SaleCampaignStatus.rejected,
  'CANCELLED' => SaleCampaignStatus.cancelled,
  _ => throw ArgumentError('Unknown sale campaign status: $value'),
};

extension SaleCampaignStatusX on SaleCampaignStatus {
  String get apiValue => switch (this) {
    SaleCampaignStatus.pendingApproval => 'PENDING_APPROVAL',
    SaleCampaignStatus.scheduled => 'SCHEDULED',
    SaleCampaignStatus.active => 'ACTIVE',
    SaleCampaignStatus.ended => 'ENDED',
    SaleCampaignStatus.rejected => 'REJECTED',
    SaleCampaignStatus.cancelled => 'CANCELLED',
  };

  String get label => switch (this) {
    SaleCampaignStatus.pendingApproval => 'Pending approval',
    SaleCampaignStatus.scheduled => 'Scheduled',
    SaleCampaignStatus.active => 'Active',
    SaleCampaignStatus.ended => 'Ended',
    SaleCampaignStatus.rejected => 'Rejected',
    SaleCampaignStatus.cancelled => 'Cancelled',
  };

  bool get isPending => this == SaleCampaignStatus.pendingApproval;
  bool get canCancel => this == SaleCampaignStatus.scheduled || this == SaleCampaignStatus.active;

  /// Only a still-unreviewed request can be freely edited — see `PATCH /sales/:id`.
  bool get canEdit => this == SaleCampaignStatus.pendingApproval;

  /// A decided campaign (approved, ended, or refused) can be brought back for a fresh approval —
  /// see `POST /sales/:id/reopen`. Pending itself is excluded: that's what edit is for.
  bool get canReopen =>
      this == SaleCampaignStatus.scheduled ||
      this == SaleCampaignStatus.active ||
      this == SaleCampaignStatus.ended ||
      this == SaleCampaignStatus.rejected ||
      this == SaleCampaignStatus.cancelled;
}

enum SaleDiscountType { percent, fixedAmount, fixedPrice }

SaleDiscountType saleDiscountTypeFromJson(String value) => switch (value) {
  'PERCENT' => SaleDiscountType.percent,
  'FIXED_AMOUNT' => SaleDiscountType.fixedAmount,
  'FIXED_PRICE' => SaleDiscountType.fixedPrice,
  _ => throw ArgumentError('Unknown sale discount type: $value'),
};

extension SaleDiscountTypeX on SaleDiscountType {
  String get apiValue => switch (this) {
    SaleDiscountType.percent => 'PERCENT',
    SaleDiscountType.fixedAmount => 'FIXED_AMOUNT',
    SaleDiscountType.fixedPrice => 'FIXED_PRICE',
  };

  String get label => switch (this) {
    SaleDiscountType.percent => '% off',
    SaleDiscountType.fixedAmount => 'Amount off',
    SaleDiscountType.fixedPrice => 'Fixed price',
  };
}

class SaleCampaignUserRef {
  const SaleCampaignUserRef({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  factory SaleCampaignUserRef.fromJson(Map<String, dynamic> json) =>
      SaleCampaignUserRef(id: json['id'] as String, fullName: json['fullName'] as String, email: json['email'] as String);
}

class SaleCampaignProductRef {
  const SaleCampaignProductRef({required this.id, required this.sku, required this.name, required this.sellingPrice});

  final String id;
  final String sku;
  final String name;
  final double sellingPrice;

  factory SaleCampaignProductRef.fromJson(Map<String, dynamic> json) => SaleCampaignProductRef(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    sellingPrice: numFromJson(json['sellingPrice']),
  );
}

/// One product's discount terms within a campaign.
class SaleCampaignProduct {
  const SaleCampaignProduct({
    required this.id,
    required this.campaignId,
    required this.productId,
    required this.discountType,
    required this.discountValue,
    required this.minQuantity,
    required this.product,
  });

  final String id;
  final String campaignId;
  final String productId;
  final SaleDiscountType discountType;
  final double discountValue;
  final double minQuantity;
  final SaleCampaignProductRef product;

  /// The resulting price, computed the same way the backend's `discountedPrice` does — for
  /// display before saving / review only; the server is always the source of truth.
  double get previewPrice {
    final raw = switch (discountType) {
      SaleDiscountType.percent => product.sellingPrice * (1 - discountValue / 100),
      SaleDiscountType.fixedAmount => product.sellingPrice - discountValue,
      SaleDiscountType.fixedPrice => discountValue,
    };
    return raw < 0 ? 0 : (raw * 100).round() / 100;
  }

  factory SaleCampaignProduct.fromJson(Map<String, dynamic> json) => SaleCampaignProduct(
    id: json['id'] as String,
    campaignId: json['campaignId'] as String,
    productId: json['productId'] as String,
    discountType: saleDiscountTypeFromJson(json['discountType'] as String),
    discountValue: numFromJson(json['discountValue']),
    minQuantity: numFromJson(json['minQuantity']),
    product: SaleCampaignProductRef.fromJson(json['product'] as Map<String, dynamic>),
  );
}

/// Mirrors `GET/POST /sales`, `POST /sales/:id/{approve,reject,cancel}`
/// (warehouse-node's `sales` module) — a named, time-windowed, per-product discount, two-step
/// approved (separation of duties enforced server-side) and flipped SCHEDULED->ACTIVE->ENDED by a
/// server-side cron tick, never by a client action.
class SaleCampaign {
  const SaleCampaign({
    required this.id,
    required this.name,
    this.description,
    required this.startsAt,
    required this.endsAt,
    required this.eligibility,
    required this.status,
    required this.requestedBy,
    required this.requestedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.dailyWindowStart,
    this.dailyWindowEnd,
    this.maxUsesPerCustomer,
    required this.requestedByUser,
    this.reviewedByUser,
    required this.products,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final SaleEligibility eligibility;
  final SaleCampaignStatus status;
  final String requestedBy;
  final DateTime requestedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;

  /// UTC-of-day, "HH:MM:SS" — same convention as every DATETIME field (see schema.sql). Both set or
  /// both null. Use [dailyWindowStartLocal]/[dailyWindowEndLocal] to display in the viewer's time.
  final String? dailyWindowStart;
  final String? dailyWindowEnd;

  /// Null = unlimited. Enforced in ordering-backend (customer identity lives there, not here).
  final int? maxUsesPerCustomer;

  final SaleCampaignUserRef requestedByUser;
  final SaleCampaignUserRef? reviewedByUser;
  final List<SaleCampaignProduct> products;

  bool get isDailyWindow => dailyWindowStart != null;

  DateTime? get dailyWindowStartLocal => _todayAt(dailyWindowStart);
  DateTime? get dailyWindowEndLocal => _todayAt(dailyWindowEnd);

  static DateTime? _todayAt(String? hms) {
    if (hms == null) return null;
    final parts = hms.split(':').map(int.parse).toList();
    final today = DateTime.now().toUtc();
    return DateTime.utc(today.year, today.month, today.day, parts[0], parts[1], parts.length > 2 ? parts[2] : 0).toLocal();
  }

  factory SaleCampaign.fromJson(Map<String, dynamic> json) => SaleCampaign(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    eligibility: saleEligibilityFromJson(json['eligibility'] as String),
    status: saleCampaignStatusFromJson(json['status'] as String),
    requestedBy: json['requestedBy'] as String,
    requestedAt: DateTime.parse(json['requestedAt'] as String),
    reviewedBy: json['reviewedBy'] as String?,
    reviewedAt: json['reviewedAt'] == null ? null : DateTime.parse(json['reviewedAt'] as String),
    reviewNote: json['reviewNote'] as String?,
    dailyWindowStart: json['dailyWindowStart'] as String?,
    dailyWindowEnd: json['dailyWindowEnd'] as String?,
    maxUsesPerCustomer: json['maxUsesPerCustomer'] as int?,
    requestedByUser: SaleCampaignUserRef.fromJson(json['requestedByUser'] as Map<String, dynamic>),
    reviewedByUser: json['reviewedByUser'] == null ? null : SaleCampaignUserRef.fromJson(json['reviewedByUser'] as Map<String, dynamic>),
    products: (json['products'] as List<dynamic>? ?? const []).map((e) => SaleCampaignProduct.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
