import '../../../shared/json_utils.dart';

/// Mirrors the raw row `POST /inventory/receiving` and `POST /inventory/
/// transfers` both return — the ledger row `applyTransaction()` created
/// (rule 2: the ledger is the truth). Unlike `GET /inventory/transactions`,
/// these two write endpoints return the plain created row with no `product`/
/// `fromLocation`/`toLocation` includes — just the scalar ids (confirmed
/// against `ReceivingService.receive`/`TransfersService.transfer`, both of
/// which return `InventoryService.applyTransaction()`'s result directly).
class InventoryTransaction {
  const InventoryTransaction({
    required this.id,
    required this.type,
    required this.productId,
    this.fromLocationId,
    this.toLocationId,
    required this.quantity,
    this.reason,
    this.reference,
    this.orderId,
    required this.performedBy,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String productId;
  final String? fromLocationId;
  final String? toLocationId;
  final double quantity;
  final String? reason;
  final String? reference;
  final String? orderId;
  final String performedBy;
  final DateTime createdAt;

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) => InventoryTransaction(
    id: json['id'] as String,
    type: json['type'] as String,
    productId: json['productId'] as String,
    fromLocationId: json['fromLocationId'] as String?,
    toLocationId: json['toLocationId'] as String?,
    quantity: numFromJson(json['quantity']),
    reason: json['reason'] as String?,
    reference: json['reference'] as String?,
    orderId: json['orderId'] as String?,
    performedBy: json['performedBy'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
