import '../../locations/domain/location.dart';
import 'inventory_balance.dart';

/// One row of the "where is this product" breakdown: a balance plus its
/// location resolved to a full Warehouse → ... → Bin path — the real
/// `GET /inventory/balances` response only embeds the location's own
/// `{id, name, code, warehouseId}` (see `InventoryBalanceLocationRef`), so
/// the path is resolved client-side (see `productStockBreakdownProvider`).
class ProductLocationStock {
  const ProductLocationStock({required this.balance, required this.warehouseName, required this.path});

  final InventoryBalance balance;
  final String warehouseName;

  /// The location's own ancestor chain, root-first, INCLUDING the balance's
  /// location itself as the last element. Does not include the warehouse —
  /// that's [warehouseName].
  final List<Location> path;

  /// "Warehouse → Zone → ... → Bin", the full path the spec asks for.
  String get fullPathLabel => [warehouseName, ...path.map((location) => location.name)].join(' › ');
}
