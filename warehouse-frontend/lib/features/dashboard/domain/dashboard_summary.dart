/// Mirrors `GET /dashboard` (`DashboardController`/`ReportsService`, gated
/// `reports.view`) field-for-field. Every number in here is a DB-level
/// aggregate the backend computed — this file only parses, never recomputes
/// anything.
library;

class CatalogueSummary {
  const CatalogueSummary({
    required this.activeProductCount,
    required this.activeCategoryCount,
    required this.activeWorkstreamCount,
    required this.activeWarehouseCount,
  });

  final int activeProductCount;
  final int activeCategoryCount;
  final int activeWorkstreamCount;
  final int activeWarehouseCount;

  factory CatalogueSummary.fromJson(Map<String, dynamic> json) => CatalogueSummary(
    activeProductCount: json['activeProductCount'] as int,
    activeCategoryCount: json['activeCategoryCount'] as int,
    activeWorkstreamCount: json['activeWorkstreamCount'] as int,
    activeWarehouseCount: json['activeWarehouseCount'] as int,
  );
}

class LowStockItem {
  const LowStockItem({
    required this.productId,
    required this.sku,
    required this.name,
    required this.onHand,
    required this.minStockLevel,
    required this.shortfall,
  });

  final String productId;
  final String sku;
  final String name;
  final double onHand;
  final double minStockLevel;
  final double shortfall;

  factory LowStockItem.fromJson(Map<String, dynamic> json) => LowStockItem(
    productId: json['productId'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    onHand: (json['onHand'] as num).toDouble(),
    minStockLevel: (json['minStockLevel'] as num).toDouble(),
    shortfall: (json['shortfall'] as num).toDouble(),
  );
}

class LowStockSummary {
  const LowStockSummary({required this.count, required this.items});

  final int count;
  final List<LowStockItem> items;

  factory LowStockSummary.fromJson(Map<String, dynamic> json) => LowStockSummary(
    count: json['count'] as int,
    // The dashboard payload calls this `topItems`; the standalone
    // `/reports/low-stock` endpoint calls the (full) list `items` — accept
    // either key so this one model serves both.
    items: ((json['topItems'] ?? json['items']) as List<dynamic>)
        .map((e) => LowStockItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A person or "—" reference embedded on an adjustment row
/// (`requestedByUser`/`reviewedByUser`) — deliberately not the richer
/// `AuditLogUserRef` from the audit feature; this is its own small shape.
class AdjustmentUserRef {
  const AdjustmentUserRef({required this.id, required this.fullName});

  final String id;
  final String fullName;

  factory AdjustmentUserRef.fromJson(Map<String, dynamic> json) =>
      AdjustmentUserRef(id: json['id'] as String, fullName: json['fullName'] as String);
}

class PendingAdjustmentItem {
  const PendingAdjustmentItem({
    required this.id,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.locationName,
    required this.locationCode,
    required this.bucket,
    required this.delta,
    required this.direction,
    required this.reason,
    required this.requestedBy,
    required this.requestedAt,
    required this.waitingDays,
  });

  final String id;
  final String productId;
  final String productSku;
  final String productName;
  final String locationName;
  final String locationCode;
  final String bucket;
  final double delta;
  final String direction;
  final String reason;
  final AdjustmentUserRef requestedBy;
  final DateTime requestedAt;
  final int waitingDays;

  factory PendingAdjustmentItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>;
    final location = json['location'] as Map<String, dynamic>;
    return PendingAdjustmentItem(
      id: json['id'] as String,
      productId: product['id'] as String,
      productSku: product['sku'] as String,
      productName: product['name'] as String,
      locationName: location['name'] as String,
      locationCode: location['code'] as String,
      bucket: json['bucket'] as String,
      delta: double.parse(json['delta'] as String),
      direction: json['direction'] as String,
      reason: json['reason'] as String,
      requestedBy: AdjustmentUserRef.fromJson(json['requestedByUser'] as Map<String, dynamic>),
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      waitingDays: json['waitingDays'] as int,
    );
  }
}

class PendingAdjustmentsSummary {
  const PendingAdjustmentsSummary({required this.count, required this.items});

  final int count;
  final List<PendingAdjustmentItem> items;

  factory PendingAdjustmentsSummary.fromJson(Map<String, dynamic> json) => PendingAdjustmentsSummary(
    count: json['count'] as int,
    items: ((json['oldestItems'] ?? json['oldestPending']) as List<dynamic>)
        .map((e) => PendingAdjustmentItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ValuationProduct {
  const ValuationProduct({
    required this.productId,
    required this.sku,
    required this.name,
    required this.onHand,
    required this.costPrice,
    required this.value,
  });

  final String productId;
  final String sku;
  final String name;
  final double onHand;
  final double costPrice;
  final double value;

  factory ValuationProduct.fromJson(Map<String, dynamic> json) => ValuationProduct(
    productId: json['productId'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    onHand: (json['onHand'] as num).toDouble(),
    costPrice: (json['costPrice'] as num).toDouble(),
    value: (json['value'] as num).toDouble(),
  );
}

class ValuationSummary {
  const ValuationSummary({required this.total, required this.excludedProductCount, required this.topProducts});

  final double total;
  final int excludedProductCount;
  final List<ValuationProduct> topProducts;

  factory ValuationSummary.fromJson(Map<String, dynamic> json) => ValuationSummary(
    total: (json['total'] as num).toDouble(),
    excludedProductCount: json['excludedProductCount'] as int,
    topProducts: (json['topProducts'] as List<dynamic>)
        .map((e) => ValuationProduct.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class StockMovementActivity {
  const StockMovementActivity({
    required this.id,
    required this.type,
    required this.productSku,
    required this.productName,
    required this.quantity,
    required this.fromLocationLabel,
    required this.toLocationLabel,
    required this.performedByName,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String productSku;
  final String productName;
  final double quantity;
  final String? fromLocationLabel;
  final String? toLocationLabel;
  final String performedByName;
  final DateTime createdAt;

  factory StockMovementActivity.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>;
    final fromLocation = json['fromLocation'] as Map<String, dynamic>?;
    final toLocation = json['toLocation'] as Map<String, dynamic>?;
    final performedByUser = json['performedByUser'] as Map<String, dynamic>?;
    return StockMovementActivity(
      id: json['id'] as String,
      type: json['type'] as String,
      productSku: product['sku'] as String,
      productName: product['name'] as String,
      quantity: double.parse(json['quantity'] as String),
      fromLocationLabel: fromLocation == null ? null : '${fromLocation['name']} (${fromLocation['code']})',
      toLocationLabel: toLocation == null ? null : '${toLocation['name']} (${toLocation['code']})',
      performedByName: performedByUser?['fullName'] as String? ?? '—',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class StockMovementSummary {
  const StockMovementSummary({required this.periodDays, required this.byType, required this.recentActivity});

  final int periodDays;
  final Map<String, int> byType;
  final List<StockMovementActivity> recentActivity;

  factory StockMovementSummary.fromJson(Map<String, dynamic> json) => StockMovementSummary(
    periodDays: json['periodDays'] as int,
    byType: (json['byType'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
    recentActivity: (json['recentActivity'] as List<dynamic>)
        .map((e) => StockMovementActivity.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class OpenStockCountsSummary {
  const OpenStockCountsSummary({required this.count});

  final int count;

  factory OpenStockCountsSummary.fromJson(Map<String, dynamic> json) =>
      OpenStockCountsSummary(count: json['count'] as int);
}

class DashboardSummary {
  const DashboardSummary({
    required this.catalogue,
    required this.lowStock,
    required this.pendingAdjustments,
    required this.valuation,
    required this.stockMovement,
    required this.openStockCounts,
  });

  final CatalogueSummary catalogue;
  final LowStockSummary lowStock;
  final PendingAdjustmentsSummary pendingAdjustments;
  final ValuationSummary valuation;
  final StockMovementSummary stockMovement;
  final OpenStockCountsSummary openStockCounts;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
    catalogue: CatalogueSummary.fromJson(json['catalogue'] as Map<String, dynamic>),
    lowStock: LowStockSummary.fromJson(json['lowStock'] as Map<String, dynamic>),
    pendingAdjustments: PendingAdjustmentsSummary.fromJson(json['pendingAdjustments'] as Map<String, dynamic>),
    valuation: ValuationSummary.fromJson(json['valuation'] as Map<String, dynamic>),
    stockMovement: StockMovementSummary.fromJson(json['stockMovement'] as Map<String, dynamic>),
    openStockCounts: OpenStockCountsSummary.fromJson(json['openStockCounts'] as Map<String, dynamic>),
  );
}
