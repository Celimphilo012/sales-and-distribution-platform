import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/stock_adjustment.dart';

/// `GET/POST /inventory/adjustments`, `POST /inventory/adjustments/:id/
/// {approve,reject}`, `GET /inventory/adjustments/:id/photo` — confirmed
/// against `StockAdjustmentsController`/`StockAdjustmentsService`.
/// `approve`/`reject` both require the adjustment to still be PENDING;
/// `approve` additionally 403s (`ForbiddenError`) if the caller is the
/// original requester (separation of duties, enforced backend-side
/// regardless of what the UI already hides).
class StockAdjustmentsApi {
  StockAdjustmentsApi(this._apiClient);

  final ApiClient _apiClient;

  /// Always multipart — an optional photo travels alongside the same fields
  /// a plain JSON POST would send, since the backend's `create` route reads
  /// both from the one request (`FileInterceptor` + a validated `@Body()`
  /// DTO together). `photoBytes`/`photoFileName` are both-or-neither.
  Future<StockAdjustment> create({
    required String productId,
    required String locationId,
    required AdjustmentBucket bucket,
    required double delta,
    required AdjustmentDirection direction,
    required String reason,
    String? reference,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    final photo = photoBytes == null
        ? null
        : MultipartFile.fromBytes(photoBytes, filename: photoFileName ?? 'photo.jpg');
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/inventory/adjustments',
        data: FormData.fromMap({
          'productId': productId,
          'locationId': locationId,
          'bucket': bucket.apiValue,
          'delta': delta.toString(),
          'direction': direction.apiValue,
          'reason': reason,
          'reference': ?reference,
          'photo': ?photo,
        }),
      ),
    );
    return StockAdjustment.fromJson(response.data!);
  }

  /// Fetches an attached photo's raw bytes (auth is attached automatically
  /// by the same `ApiClient` every other call goes through — this is NOT a
  /// plain public URL an `<img>`/`Image.network` could load directly).
  Future<Uint8List> getPhotoBytes(String adjustmentId) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<int>>(
        '/inventory/adjustments/$adjustmentId/photo',
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(response.data!);
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
