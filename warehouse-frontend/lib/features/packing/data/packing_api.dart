import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';
import '../domain/packing_order.dart';

/// `GET /packing` — open orders (reserved, not yet dispatched) with the lines
/// THIS user can act on: their warehouses, and their workstreams if they
/// manage specific ones. Needs `packing.view`.
class PackingApi {
  PackingApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<PackingOrder>> openOrders() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/packing'));
    return response.data!.map((e) => PackingOrder.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final packingApiProvider = Provider<PackingApi>((ref) => PackingApi(ref.watch(apiClientProvider)));

/// autoDispose: coming back to the screen always shows the current list.
final packingOrdersProvider = FutureProvider.autoDispose<List<PackingOrder>>((ref) {
  return ref.watch(packingApiProvider).openOrders();
});
