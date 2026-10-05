import '../../payments/domain/payment.dart';

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}

/// Mirrors `expenses.category` (`ordering-backend/db/schema.sql`). A starting
/// default list — confirm/adjust against how the business actually
/// categorizes outgoings.
enum ExpenseCategory { rent, salaries, utilities, transport, marketing, supplies, other }

extension ExpenseCategoryX on ExpenseCategory {
  String get apiValue => switch (this) {
    ExpenseCategory.rent => 'RENT',
    ExpenseCategory.salaries => 'SALARIES',
    ExpenseCategory.utilities => 'UTILITIES',
    ExpenseCategory.transport => 'TRANSPORT',
    ExpenseCategory.marketing => 'MARKETING',
    ExpenseCategory.supplies => 'SUPPLIES',
    ExpenseCategory.other => 'OTHER',
  };

  String get label => switch (this) {
    ExpenseCategory.rent => 'Rent',
    ExpenseCategory.salaries => 'Salaries',
    ExpenseCategory.utilities => 'Utilities',
    ExpenseCategory.transport => 'Transport',
    ExpenseCategory.marketing => 'Marketing',
    ExpenseCategory.supplies => 'Supplies',
    ExpenseCategory.other => 'Other',
  };
}

ExpenseCategory expenseCategoryFromJson(String value) => switch (value) {
  'RENT' => ExpenseCategory.rent,
  'SALARIES' => ExpenseCategory.salaries,
  'UTILITIES' => ExpenseCategory.utilities,
  'TRANSPORT' => ExpenseCategory.transport,
  'MARKETING' => ExpenseCategory.marketing,
  'SUPPLIES' => ExpenseCategory.supplies,
  'OTHER' => ExpenseCategory.other,
  _ => throw ArgumentError('Unknown expense category: $value'),
};

/// Money OUT — modelled directly on [Payment]: never edited or deleted, only voided (kept, with
/// who/when/why).
class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    this.description,
    required this.incurredAt,
    required this.isVoided,
    required this.recordedByName,
    this.voidedByName,
    this.voidedAt,
    this.voidReason,
  });

  final String id;
  final ExpenseCategory category;
  final double amount;
  final String? description;
  final DateTime incurredAt;
  final bool isVoided;
  final String recordedByName;
  final String? voidedByName;
  final DateTime? voidedAt;
  final String? voidReason;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    category: expenseCategoryFromJson(json['category'] as String),
    amount: _num(json['amount']),
    description: json['description'] as String?,
    incurredAt: DateTime.parse(json['incurredAt'] as String),
    isVoided: json['status'] == 'VOIDED',
    recordedByName: (json['recordedByUser'] as Map<String, dynamic>?)?['fullName'] as String? ?? '—',
    voidedByName: (json['voidedByUser'] as Map<String, dynamic>?)?['fullName'] as String?,
    voidedAt: json['voidedAt'] == null ? null : DateTime.parse(json['voidedAt'] as String),
    voidReason: json['voidReason'] as String?,
  );
}

/// One AR-aging bucket — `GET /finances/summary`.
class AgingBucket {
  const AgingBucket({required this.bucket, required this.count, required this.amount});

  /// "0-30", "31-60", "61-90" or "90+".
  final String bucket;
  final int count;
  final double amount;

  factory AgingBucket.fromJson(Map<String, dynamic> json) =>
      AgingBucket(bucket: json['bucket'] as String, count: (json['count'] as num).toInt(), amount: _num(json['amount']));
}

/// One week's revenue — `GET /finances/summary`.
class RevenuePoint {
  const RevenuePoint({required this.weekStart, required this.revenue});

  final DateTime weekStart;
  final double revenue;

  factory RevenuePoint.fromJson(Map<String, dynamic> json) =>
      RevenuePoint(weekStart: DateTime.parse(json['weekStart'] as String), revenue: _num(json['revenue']));
}

/// `GET /finances/summary` — cash collected, AR aging, a revenue trend.
class FinancesSummary {
  const FinancesSummary({
    required this.collectedAmount,
    required this.collectedCount,
    required this.outstandingAmount,
    required this.outstandingCount,
    required this.aging,
    required this.revenueTrend,
  });

  final double collectedAmount;
  final int collectedCount;
  final double outstandingAmount;
  final int outstandingCount;
  final List<AgingBucket> aging;
  final List<RevenuePoint> revenueTrend;

  factory FinancesSummary.fromJson(Map<String, dynamic> json) {
    final collected = json['collected'] as Map<String, dynamic>;
    final outstanding = json['outstanding'] as Map<String, dynamic>;
    return FinancesSummary(
      collectedAmount: _num(collected['amount']),
      collectedCount: (collected['count'] as num).toInt(),
      outstandingAmount: _num(outstanding['amount']),
      outstandingCount: (outstanding['orderCount'] as num).toInt(),
      aging: (json['aging'] as List<dynamic>).map((e) => AgingBucket.fromJson(e as Map<String, dynamic>)).toList(),
      revenueTrend: (json['revenueTrend'] as List<dynamic>).map((e) => RevenuePoint.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// One line of a customer statement — an order (+total) or a payment (-amount, 0 if voided).
class StatementEntry {
  const StatementEntry({
    required this.type,
    required this.occurredAt,
    this.orderId,
    this.orderNumber,
    required this.amount,
    required this.balance,
    this.method,
    this.isVoided = false,
  });

  /// 'ORDER' or 'PAYMENT'.
  final String type;
  final DateTime occurredAt;
  final String? orderId;
  final String? orderNumber;
  final double amount;
  final double balance;
  final PaymentMethod? method;
  final bool isVoided;

  factory StatementEntry.fromJson(Map<String, dynamic> json) => StatementEntry(
    type: json['type'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    orderId: json['orderId'] as String?,
    orderNumber: json['orderNumber'] as String?,
    amount: _num(json['amount']),
    balance: _num(json['balance']),
    method: json['method'] == null ? null : paymentMethodFromJson(json['method'] as String),
    isVoided: json['status'] == 'VOIDED',
  );
}

/// `GET /finances/statements/:customerId`.
class CustomerStatement {
  const CustomerStatement({
    required this.customerId,
    required this.customerName,
    required this.bought,
    required this.paid,
    required this.balanceDue,
    required this.entries,
  });

  final String customerId;
  final String customerName;
  final double bought;
  final double paid;
  final double balanceDue;
  final List<StatementEntry> entries;

  factory CustomerStatement.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>;
    return CustomerStatement(
      customerId: customer['id'] as String,
      customerName: customer['name'] as String,
      bought: _num(json['bought']),
      paid: _num(json['paid']),
      balanceDue: _num(json['balanceDue']),
      entries: (json['entries'] as List<dynamic>).map((e) => StatementEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// One product's margin — `GET /finances/margin`.
class MarginProductRow {
  const MarginProductRow({required this.productId, required this.productName, required this.quantity, required this.revenue, required this.margin});

  final String productId;
  final String? productName;
  final double quantity;
  final double revenue;
  final double margin;

  factory MarginProductRow.fromJson(Map<String, dynamic> json) => MarginProductRow(
    productId: json['productId'] as String,
    productName: json['productName'] as String?,
    quantity: _num(json['quantity']),
    revenue: _num(json['revenue']),
    margin: _num(json['margin']),
  );
}

/// `GET /finances/margin` — forward-looking only (see the screen's own caveat text): a line
/// placed before unit_cost snapshotting shipped has no known cost and is excluded, not zeroed.
class MarginReport {
  const MarginReport({
    required this.totalRevenue,
    required this.knownCostRevenue,
    required this.knownCostRevenuePct,
    required this.margin,
    required this.products,
  });

  final double totalRevenue;
  final double knownCostRevenue;
  final double knownCostRevenuePct;
  final double margin;
  final List<MarginProductRow> products;

  factory MarginReport.fromJson(Map<String, dynamic> json) => MarginReport(
    totalRevenue: _num(json['totalRevenue']),
    knownCostRevenue: _num(json['knownCostRevenue']),
    knownCostRevenuePct: _num(json['knownCostRevenuePct']),
    margin: _num(json['margin']),
    products: (json['products'] as List<dynamic>).map((e) => MarginProductRow.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
