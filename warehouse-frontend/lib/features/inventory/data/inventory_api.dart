import '../../../core/network/api_client.dart';
import '../domain/inventory_balance.dart';
import '../domain/inventory_unit.dart';
import '../domain/ledger_entry.dart';

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
  Future<List<InventoryBalance>> balances({String? productId, String? locationId, String? warehouseId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/inventory/balances',
        queryParameters: {'productId': ?productId, 'locationId': ?locationId, 'warehouseId': ?warehouseId},
      ),
    );
    return response.data!.map((e) => InventoryBalance.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /inventory/transactions` — the ledger, newest first, optionally by
  /// product / location / type, capped at [limit] rows.
  Future<List<LedgerEntry>> transactions({String? productId, String? locationId, String? type, int? limit}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/inventory/transactions',
        queryParameters: {'productId': ?productId, 'locationId': ?locationId, 'type': ?type, 'limit': ?limit},
      ),
    );
    return response.data!.map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /inventory/units` — one SERIAL product's physical units, paginated, newest first.
  Future<InventoryUnitsPage> units({required String productId, InventoryUnitStatus? status, int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>(
        '/inventory/units',
        queryParameters: {'productId': productId, 'status': ?status?.toJson(), 'page': page, 'pageSize': pageSize},
      ),
    );
    return InventoryUnitsPage.fromJson(response.data!);
  }
}
