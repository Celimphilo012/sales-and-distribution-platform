import '../../../core/network/api_client.dart';
import '../domain/stock_count.dart';

/// One line of a submit request: the physically counted quantity for a
/// product already snapshotted into this count's `items`.
class SubmitCountItem {
  const SubmitCountItem({required this.productId, required this.countedQty});

  final String productId;
  final double countedQty;
}

/// `POST/GET /inventory/counts`, `PATCH /inventory/counts/:id` — confirmed
/// against `StockCountsController`/`StockCountsService`. `start` omits
/// `productIds` (snapshots every product with an existing balance at the
/// location) rather than exposing product-scoped counts, matching the 6e-2
/// spec's "select a warehouse/location scope" flow.
class StockCountsApi {
  StockCountsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<StockCount> start({required String locationId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/inventory/counts', data: {'locationId': locationId}),
    );
    return StockCount.fromJson(response.data!);
  }

  Future<List<StockCount>> list({StockCountStatus? status, String? locationId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/inventory/counts',
        queryParameters: {'status': ?status?.apiValue, 'locationId': ?locationId},
      ),
    );
    return response.data!.map((e) => StockCount.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockCount> getOne(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/inventory/counts/$id'));
    return StockCount.fromJson(response.data!);
  }

  /// Records counted quantities and computes variances. Per
  /// `StockCountsService.submit`, [items] must cover EXACTLY the products
  /// snapshotted at `start` — the backend 400s on missing/extra products.
  /// Stock never moves here; the response's `createdAdjustmentIds` lists the
  /// PENDING adjustments created for nonzero variances.
  Future<StockCount> submit(String id, {required List<SubmitCountItem> items}) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/inventory/counts/$id',
        data: {
          'items': [for (final item in items) {'productId': item.productId, 'countedQty': item.countedQty}],
        },
      ),
    );
    return StockCount.fromJson(response.data!);
  }
}
