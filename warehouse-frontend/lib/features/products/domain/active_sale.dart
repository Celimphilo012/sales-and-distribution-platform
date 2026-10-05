import '../../../shared/json_utils.dart';
import '../../sales/domain/sale_campaign.dart';

/// The product-level `sale` block `GET /products` embeds (warehouse-node's `attachActiveSale`)
/// when a product is currently ON an ACTIVE campaign — read-only, shown on the product sheet.
class ActiveSale {
  const ActiveSale({
    required this.campaignId,
    required this.campaignName,
    required this.discountType,
    required this.discountValue,
    required this.minQuantity,
    required this.eligibility,
    this.effectivePrice,
    this.maxUsesPerCustomer,
  });

  final String campaignId;
  final String campaignName;
  final SaleDiscountType discountType;
  final double discountValue;
  final double minQuantity;
  final SaleEligibility eligibility;

  /// Null for a RESTRICTED campaign — the warehouse never resolves a customer-specific price.
  final double? effectivePrice;

  /// Null = unlimited.
  final int? maxUsesPerCustomer;

  factory ActiveSale.fromJson(Map<String, dynamic> json) => ActiveSale(
    campaignId: json['campaignId'] as String,
    campaignName: json['campaignName'] as String,
    discountType: saleDiscountTypeFromJson(json['discountType'] as String),
    discountValue: numFromJson(json['discountValue']),
    minQuantity: numFromJson(json['minQuantity']),
    eligibility: saleEligibilityFromJson(json['eligibility'] as String),
    effectivePrice: json['effectivePrice'] == null ? null : numFromJson(json['effectivePrice']),
    maxUsesPerCustomer: json['maxUsesPerCustomer'] as int?,
  );
}
