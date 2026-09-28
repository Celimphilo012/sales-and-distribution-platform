/// `{ id, name, code }` summaries the packing list embeds.
class PackingRef {
  const PackingRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory PackingRef.fromJson(Map<String, dynamic> json) =>
      PackingRef(id: json['id'] as String, name: json['name'] as String, code: json['code'] as String? ?? '');
}

/// One item to pick and pack: how many, of what, from where.
class PackingLine {
  const PackingLine({
    required this.id,
    required this.quantity,
    required this.sku,
    required this.productName,
    required this.uom,
    required this.workstream,
    required this.location,
    required this.warehouse,
  });

  final String id;
  final double quantity;
  final String sku;
  final String productName;
  final String uom;
  final PackingRef workstream;
  final PackingRef location;
  final PackingRef warehouse;

  factory PackingLine.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>;
    return PackingLine(
      id: json['id'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      sku: product['sku'] as String,
      productName: product['name'] as String,
      uom: product['uom'] as String,
      workstream: PackingRef.fromJson(json['workstream'] as Map<String, dynamic>),
      location: PackingRef.fromJson(json['location'] as Map<String, dynamic>),
      warehouse: PackingRef.fromJson(json['warehouse'] as Map<String, dynamic>),
    );
  }
}

/// An order waiting to be packed. [label] is what the ordering system sent
/// (e.g. "ORD-0012 · Customer"); [lines] are only the ones this user can
/// see, out of [totalLineCount] in the whole order.
class PackingOrder {
  const PackingOrder({
    required this.reference,
    required this.label,
    required this.reservedAt,
    required this.totalLineCount,
    required this.lines,
  });

  final String reference;
  final String? label;
  final DateTime reservedAt;
  final int totalLineCount;
  final List<PackingLine> lines;

  /// Human title: the label when the ordering system sent one.
  String get title => (label == null || label!.isEmpty) ? 'Order ${reference.substring(0, 8)}' : label!;

  factory PackingOrder.fromJson(Map<String, dynamic> json) => PackingOrder(
    reference: json['reference'] as String,
    label: json['label'] as String?,
    reservedAt: DateTime.parse(json['reservedAt'] as String),
    totalLineCount: (json['totalLineCount'] as num).toInt(),
    lines: (json['lines'] as List<dynamic>).map((e) => PackingLine.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
