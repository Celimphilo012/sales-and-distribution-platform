/// Mirrors the backend's `OrderStatus` enum (ARCHITECTURE.md §I) — the full
/// lifecycle. STEP R3a only ever WRITES `DRAFT` (via create/update); every
/// other value is reachable only through lifecycle actions this app doesn't
/// expose yet (R3b: submit/approve/reject/reserve/cancel/pick/pack/ready/
/// dispatch/deliver/complete — all already live on the real backend).
enum OrderStatus {
  draft,
  submitted,
  pendingApproval,
  approved,
  stockReserved,
  rejected,
  cancelled,
  picking,
  packed,
  readyForDispatch,
  dispatched,
  partiallyFulfilled,
  delivered,
  completed,
}

OrderStatus orderStatusFromJson(String value) => switch (value) {
  'DRAFT' => OrderStatus.draft,
  'SUBMITTED' => OrderStatus.submitted,
  'PENDING_APPROVAL' => OrderStatus.pendingApproval,
  'APPROVED' => OrderStatus.approved,
  'STOCK_RESERVED' => OrderStatus.stockReserved,
  'REJECTED' => OrderStatus.rejected,
  'CANCELLED' => OrderStatus.cancelled,
  'PICKING' => OrderStatus.picking,
  'PACKED' => OrderStatus.packed,
  'READY_FOR_DISPATCH' => OrderStatus.readyForDispatch,
  'DISPATCHED' => OrderStatus.dispatched,
  'PARTIALLY_FULFILLED' => OrderStatus.partiallyFulfilled,
  'DELIVERED' => OrderStatus.delivered,
  'COMPLETED' => OrderStatus.completed,
  _ => throw ArgumentError('Unknown order status: $value'),
};

extension OrderStatusX on OrderStatus {
  String get apiValue => switch (this) {
    OrderStatus.draft => 'DRAFT',
    OrderStatus.submitted => 'SUBMITTED',
    OrderStatus.pendingApproval => 'PENDING_APPROVAL',
    OrderStatus.approved => 'APPROVED',
    OrderStatus.stockReserved => 'STOCK_RESERVED',
    OrderStatus.rejected => 'REJECTED',
    OrderStatus.cancelled => 'CANCELLED',
    OrderStatus.picking => 'PICKING',
    OrderStatus.packed => 'PACKED',
    OrderStatus.readyForDispatch => 'READY_FOR_DISPATCH',
    OrderStatus.dispatched => 'DISPATCHED',
    OrderStatus.partiallyFulfilled => 'PARTIALLY_FULFILLED',
    OrderStatus.delivered => 'DELIVERED',
    OrderStatus.completed => 'COMPLETED',
  };

  String get label => switch (this) {
    OrderStatus.draft => 'Draft',
    OrderStatus.submitted => 'Submitted',
    OrderStatus.pendingApproval => 'Pending approval',
    OrderStatus.approved => 'Approved',
    OrderStatus.stockReserved => 'Stock reserved',
    OrderStatus.rejected => 'Rejected',
    OrderStatus.cancelled => 'Cancelled',
    OrderStatus.picking => 'Picking',
    OrderStatus.packed => 'Packed',
    OrderStatus.readyForDispatch => 'Ready for dispatch',
    OrderStatus.dispatched => 'Dispatched',
    OrderStatus.partiallyFulfilled => 'Partially fulfilled',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.completed => 'Completed',
  };
}

/// Rule 6: separate from [OrderStatus], never advanced by a status
/// transition — `payments` (a later phase) is what moves this.
enum PaymentStatus { unpaid, partial, paid }

PaymentStatus paymentStatusFromJson(String value) => switch (value) {
  'UNPAID' => PaymentStatus.unpaid,
  'PARTIAL' => PaymentStatus.partial,
  'PAID' => PaymentStatus.paid,
  _ => throw ArgumentError('Unknown payment status: $value'),
};

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
    PaymentStatus.unpaid => 'Unpaid',
    PaymentStatus.partial => 'Partially paid',
    PaymentStatus.paid => 'Paid',
  };
}

class OrderCustomerRef {
  const OrderCustomerRef({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;

  factory OrderCustomerRef.fromJson(Map<String, dynamic> json) =>
      OrderCustomerRef(id: json['id'] as String, name: json['name'] as String, phone: json['phone'] as String?);
}

class OrderConsultantRef {
  const OrderConsultantRef({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  factory OrderConsultantRef.fromJson(Map<String, dynamic> json) => OrderConsultantRef(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    email: json['email'] as String,
  );
}

/// One order line. `productName`/`unitPrice`/`lineTotal` are SERVER
/// SNAPSHOTS taken at write time (`OrdersService.buildLineInputs`, rule 8)
/// — never client-computed, always displayed exactly as returned.
/// `quantityPicked`/`quantityPacked`/`quantityFulfilled` are R3b fulfilment
/// fields; always 0 on a DRAFT order, shown here for completeness on the
/// read-only detail view.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    this.productName,
    required this.quantityOrdered,
    required this.quantityFulfilled,
    required this.quantityPicked,
    required this.quantityPacked,
    required this.unitPrice,
    required this.lineTotal,
    this.reservedLocationId,
    this.allocations = const [],
    this.originalUnitPrice,
    this.saleCampaignId,
    this.saleCampaignName,
  });

  final String id;
  final String orderId;
  final String productId;
  final String? productName;
  final double quantityOrdered;
  final double quantityFulfilled;
  final double quantityPicked;
  final double quantityPacked;
  final double unitPrice;
  final double lineTotal;
  final String? reservedLocationId;

  /// Set only when a sale discount applied at save time (see ordering-backend's `buildLineInputs`)
  /// — [unitPrice] is already the discounted price; this is what it would have been otherwise.
  final double? originalUnitPrice;
  final String? saleCampaignId;
  final String? saleCampaignName;
  bool get wasDiscounted => saleCampaignId != null;

  /// Where this line's stock is reserved, in plan order (oldest stock
  /// first). Several entries when a line was split across locations.
  final List<ItemAllocation> allocations;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as String,
    orderId: json['orderId'] as String,
    productId: json['productId'] as String,
    productName: json['productName'] as String?,
    quantityOrdered: _num(json['quantityOrdered']),
    quantityFulfilled: _num(json['quantityFulfilled']),
    quantityPicked: _num(json['quantityPicked']),
    quantityPacked: _num(json['quantityPacked']),
    unitPrice: _num(json['unitPrice']),
    lineTotal: _num(json['lineTotal']),
    reservedLocationId: json['reservedLocationId'] as String?,
    allocations: (json['allocations'] as List<dynamic>? ?? const [])
        .map((e) => ItemAllocation.fromJson(e as Map<String, dynamic>))
        .toList(),
    originalUnitPrice: json['originalUnitPrice'] == null ? null : _num(json['originalUnitPrice']),
    saleCampaignId: json['saleCampaignId'] as String?,
    saleCampaignName: json['saleCampaignName'] as String?,
  );
}

/// Part of a line's reservation: [quantity] held at one warehouse location.
/// [locationLabel] is the location's name as it was when reserved (a
/// snapshot, like the line's product name) — null for lines reserved before
/// names were recorded.
class ItemAllocation {
  const ItemAllocation({required this.locationId, this.locationLabel, required this.quantity});

  final String locationId;
  final String? locationLabel;
  final double quantity;

  factory ItemAllocation.fromJson(Map<String, dynamic> json) => ItemAllocation(
    locationId: json['locationId'] as String,
    locationLabel: json['locationLabel'] as String?,
    quantity: _num(json['quantity']),
  );
}

class OrderStatusHistoryEntry {
  const OrderStatusHistoryEntry({
    required this.id,
    this.fromStatus,
    required this.toStatus,
    required this.changedByName,
    this.note,
    required this.createdAt,
  });

  final String id;
  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final String changedByName;
  final String? note;
  final DateTime createdAt;

  factory OrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) => OrderStatusHistoryEntry(
    id: json['id'] as String,
    fromStatus: json['fromStatus'] == null ? null : orderStatusFromJson(json['fromStatus'] as String),
    toStatus: orderStatusFromJson(json['toStatus'] as String),
    changedByName: (json['changedByUser'] as Map<String, dynamic>?)?['fullName'] as String? ?? '—',
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Mirrors `GET/POST/PATCH /orders` (`OrdersController`/`OrdersService`).
/// `total` is the server-computed sum of snapshotted `lineTotal`s — never
/// recomputed client-side (rule 8's spirit extended to the order total).
class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    this.consultantId,
    required this.status,
    required this.paymentStatus,
    required this.orderDate,
    this.deliveryInfo,
    required this.total,
    this.amountPaid = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.customer,
    this.consultant,
    required this.items,
    this.statusHistory = const [],
  });

  final String id;
  final String orderNumber;
  final String customerId;
  final String? consultantId;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final DateTime orderDate;
  final String? deliveryInfo;
  final double total;

  /// Sum of the order's RECORDED payments (server-computed; voided ones excluded).
  final double amountPaid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final OrderCustomerRef customer;
  final OrderConsultantRef? consultant;
  final List<OrderItem> items;
  final List<OrderStatusHistoryEntry> statusHistory;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    orderNumber: json['orderNumber'] as String,
    customerId: json['customerId'] as String,
    consultantId: json['consultantId'] as String?,
    status: orderStatusFromJson(json['status'] as String),
    paymentStatus: paymentStatusFromJson(json['paymentStatus'] as String),
    orderDate: DateTime.parse(json['orderDate'] as String),
    deliveryInfo: json['deliveryInfo'] as String?,
    total: _num(json['total']),
    amountPaid: _num(json['amountPaid']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    customer: OrderCustomerRef.fromJson(json['customer'] as Map<String, dynamic>),
    consultant: json['consultant'] == null
        ? null
        : OrderConsultantRef.fromJson(json['consultant'] as Map<String, dynamic>),
    items: (json['items'] as List<dynamic>).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
    statusHistory: (json['statusHistory'] as List<dynamic>? ?? const [])
        .map((e) => OrderStatusHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
