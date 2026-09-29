/// `GET /orders/:id/reservation-proposal` — the backend's automatic plan for
/// reserving an APPROVED order: ONE warehouse, oldest stock first, a line
/// split across locations when no single one holds enough. Every figure
/// comes from the warehouse's live balances; the client only presents it and
/// lets a manager adjust it.
class ReservationProposal {
  const ReservationProposal({
    required this.complete,
    required this.warehouse,
    required this.alternatives,
    required this.lines,
  });

  /// True when the chosen warehouse can fill every line in full.
  final bool complete;

  /// The warehouse the plan uses, or null when nothing is in stock anywhere.
  final WarehouseChoice? warehouse;

  /// Every warehouse holding any of the order's products (including [warehouse]).
  final List<WarehouseChoice> alternatives;
  final List<ProposalLine> lines;

  factory ReservationProposal.fromJson(Map<String, dynamic> json) => ReservationProposal(
    complete: json['complete'] as bool,
    warehouse: json['warehouse'] == null ? null : WarehouseChoice.fromJson(json['warehouse'] as Map<String, dynamic>),
    alternatives: (json['alternatives'] as List<dynamic>? ?? const [])
        .map((e) => WarehouseChoice.fromJson(e as Map<String, dynamic>))
        .toList(),
    lines: (json['lines'] as List<dynamic>).map((e) => ProposalLine.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class WarehouseChoice {
  const WarehouseChoice({required this.id, required this.name, this.code, this.complete});

  final String id;
  final String name;
  final String? code;

  /// Whether this warehouse alone could fill the whole order (alternatives only).
  final bool? complete;

  factory WarehouseChoice.fromJson(Map<String, dynamic> json) => WarehouseChoice(
    id: json['id'] as String,
    name: json['name'] as String? ?? json['id'] as String,
    code: json['code'] as String?,
    complete: json['complete'] as bool?,
  );
}

/// A location in the plan's warehouse that holds the line's product.
class LocationOption {
  const LocationOption({required this.locationId, required this.label, required this.available, this.oldestStockAt});

  final String locationId;

  /// "Rack A › Shelf 2".
  final String label;
  final double available;

  /// When the oldest units still there arrived (the FIFO key), if known.
  final DateTime? oldestStockAt;

  factory LocationOption.fromJson(Map<String, dynamic> json) => LocationOption(
    locationId: json['locationId'] as String,
    label: json['label'] as String? ?? json['locationId'] as String,
    available: _num(json['available']),
    oldestStockAt: json['oldestStockAt'] == null ? null : DateTime.parse(json['oldestStockAt'] as String),
  );
}

class ProposalLine {
  const ProposalLine({
    required this.orderItemId,
    required this.productName,
    required this.quantity,
    required this.allocations,
    required this.shortBy,
    required this.options,
  });

  final String orderItemId;
  final String productName;
  final double quantity;

  /// location id → quantity the plan takes from it, oldest stock first.
  final Map<String, double> allocations;

  /// How much of the line the plan's warehouse cannot cover (0 = fully covered).
  final double shortBy;

  /// Every location in the warehouse holding this product, oldest stock first.
  final List<LocationOption> options;

  factory ProposalLine.fromJson(Map<String, dynamic> json) => ProposalLine(
    orderItemId: json['orderItemId'] as String,
    productName: json['productName'] as String? ?? json['productId'] as String,
    quantity: _num(json['quantity']),
    allocations: {
      for (final a in (json['allocations'] as List<dynamic>).cast<Map<String, dynamic>>())
        a['locationId'] as String: _num(a['quantity']),
    },
    shortBy: _num(json['shortBy']),
    options: (json['options'] as List<dynamic>).map((e) => LocationOption.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// One entry of a reservation as sent to `POST /orders/:id/reserve`.
class ReserveAllocation {
  const ReserveAllocation({required this.orderItemId, required this.locationId, required this.quantity});

  final String orderItemId;
  final String locationId;
  final double quantity;

  Map<String, dynamic> toJson() => {'orderItemId': orderItemId, 'locationId': locationId, 'quantity': quantity};
}

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
