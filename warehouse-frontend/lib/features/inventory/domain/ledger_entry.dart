/// One row of the inventory ledger as `GET /inventory/transactions` returns
/// it, with the product, both locations and who performed it — what the
/// receiving/transfer history lists and the product sheet's "Recent
/// movements" show. Receipts carry `Supplier: … | Received: … | Notes: …`
/// in [reason] (written by the receiving service), unpacked by [supplier].
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.quantity,
    required this.createdAt,
    this.fromLocationId,
    this.fromCode,
    this.fromName,
    this.toLocationId,
    this.toCode,
    this.toName,
    this.reason,
    this.reference,
    this.performedByName,
  });

  final String id;
  final String type;
  final String productId;
  final String productSku;
  final String productName;
  final double quantity;
  final DateTime createdAt;
  final String? fromLocationId;
  final String? fromCode;
  final String? fromName;
  final String? toLocationId;
  final String? toCode;
  final String? toName;
  final String? reason;
  final String? reference;
  final String? performedByName;

  /// "Supplier: Acme | Received: … " → "Acme" (receipts only).
  String? get supplier => _part('Supplier');

  String? get notes => _part('Notes');

  String? _part(String key) {
    for (final p in (reason ?? '').split('|')) {
      final t = p.trim();
      if (t.startsWith('$key:')) return t.substring(key.length + 1).trim();
    }
    return null;
  }

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? const {};
    final from = json['fromLocation'] as Map<String, dynamic>?;
    final to = json['toLocation'] as Map<String, dynamic>?;
    final by = json['performedByUser'] as Map<String, dynamic>?;
    return LedgerEntry(
      id: json['id'] as String,
      type: json['type'] as String,
      productId: json['productId'] as String,
      productSku: product['sku'] as String? ?? '',
      productName: product['name'] as String? ?? '',
      quantity: double.parse('${json['quantity']}'),
      createdAt: DateTime.parse(json['createdAt'] as String),
      fromLocationId: json['fromLocationId'] as String?,
      fromCode: from?['code'] as String?,
      fromName: from?['name'] as String?,
      toLocationId: json['toLocationId'] as String?,
      toCode: to?['code'] as String?,
      toName: to?['name'] as String?,
      reason: json['reason'] as String?,
      reference: json['reference'] as String?,
      performedByName: by?['fullName'] as String?,
    );
  }
}
