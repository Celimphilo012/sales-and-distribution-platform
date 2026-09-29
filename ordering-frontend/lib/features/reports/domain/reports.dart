import '../../orders/domain/order.dart';
import '../../payments/domain/payment.dart';

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}

/// One row of an "orders by status" breakdown.
class StatusBucket {
  const StatusBucket({required this.status, required this.count, required this.totalValue});

  final OrderStatus status;
  final int count;
  final double totalValue;

  factory StatusBucket.fromJson(Map<String, dynamic> json) => StatusBucket(
    status: orderStatusFromJson(json['status'] as String),
    count: (json['count'] as num).toInt(),
    totalValue: _num(json['totalValue']),
  );
}

/// A compact order line as the reports/dashboard return it.
class OrderSummaryRow {
  const OrderSummaryRow({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.orderDate,
    required this.total,
    required this.customerName,
    this.amountPaid,
    this.balanceDue,
  });

  final String id;
  final String orderNumber;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final DateTime orderDate;
  final double total;
  final String customerName;
  final double? amountPaid;
  final double? balanceDue;

  factory OrderSummaryRow.fromJson(Map<String, dynamic> json) => OrderSummaryRow(
    id: json['id'] as String,
    orderNumber: json['orderNumber'] as String,
    status: orderStatusFromJson(json['status'] as String),
    paymentStatus: paymentStatusFromJson(json['paymentStatus'] as String),
    orderDate: DateTime.parse(json['orderDate'] as String),
    total: _num(json['total']),
    customerName: (json['customer'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
    amountPaid: json['amountPaid'] == null ? null : _num(json['amountPaid']),
    balanceDue: json['balanceDue'] == null ? null : _num(json['balanceDue']),
  );
}

/// `GET /reports/orders`.
class OrdersReport {
  const OrdersReport({required this.count, required this.totalValue, required this.byStatus, required this.orders});

  final int count;
  final double totalValue;
  final List<StatusBucket> byStatus;
  final List<OrderSummaryRow> orders;

  factory OrdersReport.fromJson(Map<String, dynamic> json) => OrdersReport(
    count: (json['count'] as num).toInt(),
    totalValue: _num(json['totalValue']),
    byStatus: (json['byStatus'] as List<dynamic>).map((e) => StatusBucket.fromJson(e as Map<String, dynamic>)).toList(),
    orders: (json['orders'] as List<dynamic>).map((e) => OrderSummaryRow.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class MethodTotal {
  const MethodTotal({required this.method, required this.count, required this.amount});

  final PaymentMethod method;
  final int count;
  final double amount;

  factory MethodTotal.fromJson(Map<String, dynamic> json) => MethodTotal(
    method: paymentMethodFromJson(json['method'] as String),
    count: (json['count'] as num).toInt(),
    amount: _num(json['amount']),
  );
}

/// `GET /reports/payments`: money in (by method), voided, and still owed.
class PaymentsReport {
  const PaymentsReport({
    required this.collectedCount,
    required this.collectedAmount,
    required this.byMethod,
    required this.voidedCount,
    required this.voidedAmount,
    required this.outstandingCount,
    required this.outstandingAmount,
    required this.outstandingOrders,
  });

  final int collectedCount;
  final double collectedAmount;
  final List<MethodTotal> byMethod;
  final int voidedCount;
  final double voidedAmount;
  final int outstandingCount;
  final double outstandingAmount;
  final List<OrderSummaryRow> outstandingOrders;

  factory PaymentsReport.fromJson(Map<String, dynamic> json) {
    final collected = json['collected'] as Map<String, dynamic>;
    final voided = json['voided'] as Map<String, dynamic>;
    final outstanding = json['outstanding'] as Map<String, dynamic>;
    return PaymentsReport(
      collectedCount: (collected['count'] as num).toInt(),
      collectedAmount: _num(collected['amount']),
      byMethod: (collected['byMethod'] as List<dynamic>)
          .map((e) => MethodTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      voidedCount: (voided['count'] as num).toInt(),
      voidedAmount: _num(voided['amount']),
      outstandingCount: (outstanding['orderCount'] as num).toInt(),
      outstandingAmount: _num(outstanding['amount']),
      outstandingOrders: (outstanding['orders'] as List<dynamic>)
          .map((e) => OrderSummaryRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// `GET /dashboard`.
class DashboardSummary {
  const DashboardSummary({
    required this.byStatus,
    required this.todayCount,
    required this.todayValue,
    required this.todayCollected,
    required this.weekCount,
    required this.weekValue,
    required this.weekCollected,
    required this.awaitingApproval,
    required this.outstandingCount,
    required this.outstandingAmount,
    required this.recentOrders,
  });

  final List<StatusBucket> byStatus;
  final int todayCount;
  final double todayValue;
  final double todayCollected;
  final int weekCount;
  final double weekValue;
  final double weekCollected;
  final int awaitingApproval;
  final int outstandingCount;
  final double outstandingAmount;
  final List<OrderSummaryRow> recentOrders;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final today = json['today'] as Map<String, dynamic>;
    final week = json['thisWeek'] as Map<String, dynamic>;
    final outstanding = json['outstanding'] as Map<String, dynamic>? ?? const {};
    return DashboardSummary(
      byStatus: (json['ordersByStatus'] as List<dynamic>)
          .map((e) => StatusBucket.fromJson(e as Map<String, dynamic>))
          .toList(),
      todayCount: (today['orderCount'] as num).toInt(),
      todayValue: _num(today['totalValue']),
      todayCollected: _num(today['collected']),
      weekCount: (week['orderCount'] as num).toInt(),
      weekValue: _num(week['totalValue']),
      weekCollected: _num(week['collected']),
      awaitingApproval: (json['awaitingApproval'] as num? ?? 0).toInt(),
      outstandingCount: (outstanding['orderCount'] as num? ?? 0).toInt(),
      outstandingAmount: _num(outstanding['amount']),
      recentOrders: (json['recentOrders'] as List<dynamic>? ?? const [])
          .map((e) => OrderSummaryRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
