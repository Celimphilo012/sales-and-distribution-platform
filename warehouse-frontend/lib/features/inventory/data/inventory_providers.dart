import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../locations/data/locations_providers.dart';
import '../../locations/domain/location.dart';
import '../../locations/domain/location_path.dart';
import '../../products/data/products_providers.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/products_filter.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../domain/inventory_balance.dart';
import '../domain/ledger_entry.dart';
import '../domain/product_location_stock.dart';
import 'inventory_api.dart';

final inventoryApiProvider = Provider<InventoryApi>((ref) => InventoryApi(ref.watch(apiClientProvider)));

/// Product search for the "where is this product" picker — reuses the
/// catalogue's own `ProductsApi`/`ProductsFilter` (the same search the
/// Products list screen uses) rather than duplicating it. Kept as its own
/// provider (not the shared `productsFilterProvider`) so typing here never
/// disturbs the Products screen's own filter state. A blank query returns
/// no results rather than the entire catalogue.
final productSearchResultsProvider = FutureProvider.autoDispose.family<List<Product>, String>((ref, query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return Future.value(const []);
  return ref.watch(productsApiProvider).list(ProductsFilter(search: trimmed));
});

/// Raw balances for one location — "what's in this location", and the 6c
/// detail-panel's "Stock in this location" section.
final locationBalancesProvider = FutureProvider.autoDispose.family<List<InventoryBalance>, String>((ref, locationId) {
  return ref.watch(inventoryApiProvider).balances(locationId: locationId);
});

/// The single balance row for one (product, location) pair, or `null` if
/// that pair has never had stock (no row yet). Used by 6e-1's post-submit
/// confirmation card to show the fresh on_hand/reserved/available right
/// after a receive/transfer — the concrete "write→read loop" proof, without
/// rebuilding 6d's own views.
final productLocationBalanceProvider = FutureProvider.autoDispose
    .family<InventoryBalance?, ({String productId, String locationId})>((ref, args) async {
      final rows = await ref
          .watch(inventoryApiProvider)
          .balances(productId: args.productId, locationId: args.locationId);
      return rows.isEmpty ? null : rows.single;
    });

/// "Where is this product": every balance row for [productId], each
/// resolved to its full Warehouse → ... → Bin path. Reuses 6c's
/// `warehouseLocationsProvider` (one fetch per distinct warehouse the
/// product's stock touches, not per row) and `warehousesProvider` for the
/// warehouse name, rather than re-fetching location data of its own.
final productStockBreakdownProvider = FutureProvider.autoDispose
    .family<List<ProductLocationStock>, String>((ref, productId) async {
      final balances = await ref.watch(inventoryApiProvider).balances(productId: productId);
      if (balances.isEmpty) return const [];

      final warehouses = await ref.watch(warehousesProvider(true).future);
      final warehouseNameById = {for (final warehouse in warehouses) warehouse.id: warehouse.name};

      final warehouseIds = balances.map((b) => b.location.warehouseId).toSet();
      final locationsByWarehouse = <String, List<Location>>{};
      for (final warehouseId in warehouseIds) {
        locationsByWarehouse[warehouseId] = await ref.watch(
          warehouseLocationsProvider((warehouseId: warehouseId, includeInactive: true)).future,
        );
      }

      return [
        for (final balance in balances)
          ProductLocationStock(
            balance: balance,
            warehouseName: warehouseNameById[balance.location.warehouseId] ?? '(unknown warehouse)',
            path: locationPath(locationsByWarehouse[balance.location.warehouseId] ?? const [], balance.locationId),
          ),
      ];
    });

/// Every balance the viewer can see (all their warehouses) — the Inventory
/// list, the structure map's fill figures, and the transfer source picker.
final allBalancesProvider = FutureProvider.autoDispose<List<InventoryBalance>>((ref) {
  return ref.watch(inventoryApiProvider).balances();
});

/// Ledger rows of one type (RECEIVE, TRANSFER…), newest first — the receiving
/// and transfer history lists.
final ledgerByTypeProvider = FutureProvider.autoDispose.family<List<LedgerEntry>, String>((ref, type) {
  return ref.watch(inventoryApiProvider).transactions(type: type, limit: 1000);
});

/// A product's latest movements (the product sheet).
final productLedgerProvider = FutureProvider.autoDispose.family<List<LedgerEntry>, String>((ref, productId) {
  return ref.watch(inventoryApiProvider).transactions(productId: productId, limit: 8);
});

/// Everything that moves stock invalidates these.
void invalidateStockViews(WidgetRef ref) {
  ref.invalidate(allBalancesProvider);
  ref.invalidate(ledgerByTypeProvider);
  ref.invalidate(productLedgerProvider);
  ref.invalidate(productStockBreakdownProvider);
  ref.invalidate(locationBalancesProvider);
  ref.invalidate(productsListProvider);
}
