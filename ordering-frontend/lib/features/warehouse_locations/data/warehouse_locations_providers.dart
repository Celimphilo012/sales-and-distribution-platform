import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/warehouse_locations.dart';

/// `GET /warehouse-locations` — the location tree, needed only to pick where
/// each order line's stock is reserved from. Gated `orders.approve` on the
/// backend (the same key reserve itself needs).
final warehouseLocationsProvider = FutureProvider.autoDispose<WarehouseLocations>((ref) async {
  final response = await ref
      .watch(apiClientProvider)
      .guard((dio) => dio.get<Map<String, dynamic>>('/warehouse-locations'));
  return WarehouseLocations.fromJson(response.data!);
});
