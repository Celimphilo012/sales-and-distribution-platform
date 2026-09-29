import '../../orders/domain/order.dart';

/// How a customer paid. Mirrors `payments.method` (`ordering-backend/db/schema.sql`).
enum PaymentMethod { cash, mobileMoney, bankTransfer, card }

extension PaymentMethodX on PaymentMethod {
  String get apiValue => switch (this) {
    PaymentMethod.cash => 'CASH',
    PaymentMethod.mobileMoney => 'MOBILE_MONEY',
    PaymentMethod.bankTransfer => 'BANK_TRANSFER',
    PaymentMethod.card => 'CARD',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.mobileMoney => 'Mobile money (MoMo)',
    PaymentMethod.bankTransfer => 'Bank transfer / EFT',
    PaymentMethod.card => 'Card',
  };

  /// Every non-cash payment must carry the provider's reference (the backend enforces it too).
  bool get needsReference => this != PaymentMethod.cash;

  String get referenceHint => switch (this) {
    PaymentMethod.cash => 'Receipt number (optional)',
    PaymentMethod.mobileMoney => 'MoMo transaction ID',
    PaymentMethod.bankTransfer => 'Bank reference',
    PaymentMethod.card => 'Card slip number',
  };
}

PaymentMethod paymentMethodFromJson(String value) => switch (value) {
  'CASH' => PaymentMethod.cash,
  'MOBILE_MONEY' => PaymentMethod.mobileMoney,
  'BANK_TRANSFER' => PaymentMethod.bankTransfer,
  'CARD' => PaymentMethod.card,
  _ => throw ArgumentError('Unknown payment method: $value'),
};

/// One payment against an order. A mistaken payment is never edited or
/// deleted — it is VOIDED and stays on record with who voided it and why.
class Payment {
  const Payment({
    required this.id,
    required this.amount,
    required this.method,
    this.reference,
    this.notes,
    required this.paidAt,
    required this.isVoided,
    required this.recordedByName,
    this.voidedByName,
    this.voidedAt,
    this.voidReason,
    this.orderNumber,
  });

  final String id;
  final double amount;
  final PaymentMethod method;
  final String? reference;
  final String? notes;
  final DateTime paidAt;
  final bool isVoided;
  final String recordedByName;
  final String? voidedByName;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? orderNumber;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as String,
    amount: _num(json['amount']),
    method: paymentMethodFromJson(json['method'] as String),
    reference: json['reference'] as String?,
    notes: json['notes'] as String?,
    paidAt: DateTime.parse(json['paidAt'] as String),
    isVoided: json['status'] == 'VOIDED',
    recordedByName: (json['recordedByUser'] as Map<String, dynamic>?)?['fullName'] as String? ?? '—',
    voidedByName: (json['voidedByUser'] as Map<String, dynamic>?)?['fullName'] as String?,
    voidedAt: json['voidedAt'] == null ? null : DateTime.parse(json['voidedAt'] as String),
    voidReason: json['voidReason'] as String?,
    orderNumber: (json['order'] as Map<String, dynamic>?)?['orderNumber'] as String?,
  );
}

/// An order's money: `GET /payments?orderId=` (and what record/void return).
/// Every figure is server-computed — the client never adds payments up.
class OrderPayments {
  const OrderPayments({
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.paymentStatus,
    this.payments = const [],
  });

  final double total;
  final double amountPaid;
  final double balanceDue;
  final PaymentStatus paymentStatus;
  final List<Payment> payments;

  factory OrderPayments.fromJson(Map<String, dynamic> json) => OrderPayments(
    total: _num(json['total']),
    amountPaid: _num(json['amountPaid']),
    balanceDue: _num(json['balanceDue']),
    paymentStatus: paymentStatusFromJson(json['paymentStatus'] as String),
    payments: (json['payments'] as List<dynamic>? ?? const [])
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
