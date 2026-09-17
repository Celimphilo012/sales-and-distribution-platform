import '../../../core/network/api_client.dart';
import '../domain/inventory_balance.dart';

/// `GET /inventory/*` — read-only in this app (6d displays inventory; it
/// never moves stock — that's 6e's receiving/transfers/counts/adjustments).
/// Both routes on the real `InventoryController` require `inventory.view`
/// only (already a single read permission, no separate split needed here).
class InventoryApi {
  InventoryApi(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /inventory/balances` — optionally filtered to one product and/or
  /// one location (both accepted together, though callers here only ever
  /// use one at a time: by product for "where is this product", by location
  /// for "what's in this location").
  Future<List<InventoryBalance>> balances({String? productId, String? locationId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/inventory/balances',
        queryParameters: {'productId': ?productId, 'locationId': ?locationId},
      ),
    );
    return response.data!.map((e) => InventoryBalance.fromJson(e as Map<String, dynamic>)).toList();
  }
}
