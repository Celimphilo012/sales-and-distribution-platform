double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}

/// One product's discount terms within a relayed campaign — just enough to show the terms; the
/// warehouse owns the full detail (warehouse-frontend's Sale Campaigns screen).
class SaleCampaignProductSummary {
  const SaleCampaignProductSummary({
    required this.productId,
    required this.sku,
    required this.name,
    required this.discountType,
    required this.discountValue,
    required this.minQuantity,
  });

  final String productId;
  final String sku;
  final String name;
  final String discountType; // PERCENT | FIXED_AMOUNT | FIXED_PRICE
  final double discountValue;
  final double minQuantity;

  String get discountLabel => switch (discountType) {
    'PERCENT' => '${discountValue % 1 == 0 ? discountValue.toInt() : discountValue}% off',
    'FIXED_AMOUNT' => '$discountValue off',
    _ => 'fixed $discountValue',
  };

  factory SaleCampaignProductSummary.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return SaleCampaignProductSummary(
      productId: json['productId'] as String,
      sku: product?['sku'] as String? ?? '',
      name: product?['name'] as String? ?? '(unknown product)',
      discountType: json['discountType'] as String,
      discountValue: _num(json['discountValue']),
      minQuantity: _num(json['minQuantity']),
    );
  }
}

/// Mirrors `GET /sales` (ordering-backend's thin relay over the warehouse's `GET /api/v1/sales`) —
/// read-only here; campaigns themselves are scheduled/approved in `/warehouse-frontend`. Only
/// SCHEDULED/ACTIVE campaigns are ever included (see external-api/routes.js on the warehouse side).
class SaleCampaignSummary {
  const SaleCampaignSummary({
    required this.id,
    required this.name,
    this.description,
    required this.startsAt,
    required this.endsAt,
    required this.eligibility,
    required this.status,
    required this.products,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String eligibility; // ALL_CUSTOMERS | RESTRICTED
  final String status;
  final List<SaleCampaignProductSummary> products;

  bool get isRestricted => eligibility == 'RESTRICTED';

  factory SaleCampaignSummary.fromJson(Map<String, dynamic> json) => SaleCampaignSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    eligibility: json['eligibility'] as String,
    status: json['status'] as String,
    products: (json['products'] as List<dynamic>? ?? const []).map((e) => SaleCampaignProductSummary.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// One row of `GET /sales/:campaignId/eligible-consultants`. Eligibility is assigned by
/// consultant, not by individual customer — every customer whose `assignedConsultantId` points at
/// an eligible consultant qualifies for the campaign's price.
class EligibleConsultant {
  const EligibleConsultant({required this.id, required this.consultantId, required this.consultantName, this.consultantEmail});

  final String id;
  final String consultantId;
  final String consultantName;
  final String? consultantEmail;

  factory EligibleConsultant.fromJson(Map<String, dynamic> json) {
    final consultant = json['consultant'] as Map<String, dynamic>?;
    return EligibleConsultant(
      id: json['id'] as String,
      consultantId: json['consultantId'] as String,
      consultantName: consultant?['fullName'] as String? ?? '(unknown consultant)',
      consultantEmail: consultant?['email'] as String?,
    );
  }
}
