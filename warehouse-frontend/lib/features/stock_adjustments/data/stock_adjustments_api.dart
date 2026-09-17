import '../../../core/network/api_client.dart';
import '../domain/stock_adjustment.dart';

/// `GET/POST /inventory/adjustments`, `POST /inventory/adjustments/:id/
/// {approve,reject}` — confirmed against `StockAdjustmentsController`/
/// `StockAdjustmentsService`. `approve`/`reject` both require the adjustment
/// to still be PENDING; `approve` additionally 403s (`ForbiddenError`) if the
/// caller is the original requester (separation of duties, enforced
/// backend-side regardless of what the UI already hides).
class StockAdjustmentsApi {
  StockAdjustmentsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<StockAdjustment> create({
    required String productId,
    required String locationId,
    required AdjustmentBucket bucket,
    required double delta,
    required AdjustmentDirection direction,
    required String reason,
    String? reference,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/adjustments',
        data: {
          'productId': productId,
          'locationId': locationId,
          'bucket': bucket.apiValue,
          'delta': delta,
          'direction': direction.apiValue,
          'reason': reason,
          'reference': ?reference,
        },
      ),
    );
    return StockAdjustment.fromJson(response.data!);
  }

  Future<List<StockAdjustment>> list({AdjustmentStatus? status}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/inventory/adjustments',
        queryParameters: {'status': ?status?.apiValue},
      ),
    );
    return response.data!.map((e) => StockAdjustment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockAdjustment> approve(String id, {String? reviewNote}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/adjustments/$id/approve',
        data: {'reviewNote': ?reviewNote},
      ),
    );
    return StockAdjustment.fromJson(response.data!);
  }

  Future<StockAdjustment> reject(String id, {required String reviewNote}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/adjustments/$id/reject',
        data: {'reviewNote': reviewNote},
      ),
    );
    return StockAdjustment.fromJson(response.data!);
  }
}
