import '../../../shared/json_utils.dart';

/// The `{id, sku, name, uom}` the backend embeds on a balance for its
/// product — not the full `Product` (see `features/products/domain/product.dart`).
class InventoryBalanceProductRef {
  const InventoryBalanceProductRef({
    required this.id,
    required this.sku,
    required this.name,
    required this.uom,
  });

  final String id;
  final String sku;
  final String name;
  final String uom;

  factory InventoryBalanceProductRef.fromJson(Map<String, dynamic> json) => InventoryBalanceProductRef(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    uom: json['uom'] as String,
  );
}

/// The `{id, name, code, warehouseId}` the backend embeds on a balance for
/// its location. **No ancestor chain** — confirmed against the real
/// `GET /inventory/balances` response (step 6d inspection). The full
/// Warehouse → ... → Bin path is resolved client-side from the locations
/// data 6c already fetches (see `location_path.dart`).
class InventoryBalanceLocationRef {
  const InventoryBalanceLocationRef({
    required this.id,
    required this.name,
    required this.code,
    required this.warehouseId,
  });

  final String id;
  final String name;
  final String code;
  final String warehouseId;

  factory InventoryBalanceLocationRef.fromJson(Map<String, dynamic> json) => InventoryBalanceLocationRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    warehouseId: json['warehouseId'] as String,
  );
}

/// Mirrors one row of `GET /inventory/balances` (rule 3/4: `(product,
/// location, quantity)`, five distinct buckets). Every quantity field is a
/// Prisma `Decimal` and arrives as a JSON STRING (`numFromJson` parses
/// either representation) — confirmed in step 6d. `available` is computed
/// server-side as `onHand - reserved` and comes back the same way; it is
/// never sent on write (there is no write path here — 6d is read-only).
class InventoryBalance {
  const InventoryBalance({
    required this.id,
    required this.productId,
    required this.locationId,
    required this.onHand,
    required this.reserved,
    required this.damaged,
    required this.lost,
    required this.expired,
    required this.available,
    required this.product,
    required this.location,
  });

  final String id;
  final String productId;
  final String locationId;
  final double onHand;
  final double reserved;
  final double damaged;
  final double lost;
  final double expired;
  final double available;
  final InventoryBalanceProductRef product;
  final InventoryBalanceLocationRef location;

  factory InventoryBalance.fromJson(Map<String, dynamic> json) => InventoryBalance(
    id: json['id'] as String,
    productId: json['productId'] as String,
    locationId: json['locationId'] as String,
    onHand: numFromJson(json['onHand']),
    reserved: numFromJson(json['reserved']),
    damaged: numFromJson(json['damaged']),
    lost: numFromJson(json['lost']),
    expired: numFromJson(json['expired']),
    available: numFromJson(json['available']),
    product: InventoryBalanceProductRef.fromJson(json['product'] as Map<String, dynamic>),
    location: InventoryBalanceLocationRef.fromJson(json['location'] as Map<String, dynamic>),
  );
}
