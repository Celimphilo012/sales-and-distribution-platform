import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/warehouse.dart';
import 'warehouses_api.dart';

final warehousesApiProvider = Provider<WarehousesApi>((ref) => WarehousesApi(ref.watch(apiClientProvider)));

/// Keyed by `includeInactive` — the structure picker (active only) and a
/// future warehouse-management screen (everything) get independent caches.
final warehousesProvider = FutureProvider.autoDispose.family<List<Warehouse>, bool>((ref, includeInactive) {
  return ref.watch(warehousesApiProvider).list(includeInactive: includeInactive);
});

void invalidateWarehouses(WidgetRef ref) {
  ref.invalidate(warehousesProvider(true));
  ref.invalidate(warehousesProvider(false));
}
