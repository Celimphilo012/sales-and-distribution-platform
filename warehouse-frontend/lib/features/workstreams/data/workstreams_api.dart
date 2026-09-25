import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/workstream.dart';

/// All workstream API calls (`GET/POST/PATCH/DELETE /workstreams`). Gated
/// with the SAME permissions as categories/products: `catalogue.view` to
/// read, `products.manage` to create/edit/deactivate (confirmed against the
/// real backend — workstreams are catalogue-organization, not warehouse
/// structure, so they don't use `warehouse.structure.*`).
class WorkstreamsApi {
  WorkstreamsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Workstream>> list({String? warehouseId, bool includeInactive = false}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/workstreams',
        queryParameters: {'warehouseId': ?warehouseId, if (includeInactive) 'includeInactive': true},
      ),
    );
    return response.data!.map((e) => Workstream.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Workstream> create({
    required String warehouseId,
    required String name,
    required String code,
    String? description,
    String? imageUrl,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/workstreams',
        data: {
          'warehouseId': warehouseId,
          'name': name,
          'code': code,
          'description': ?description,
          'imageUrl': ?imageUrl,
          'contactName': ?contactName,
          'contactEmail': ?contactEmail,
          'contactPhone': ?contactPhone,
        },
      ),
    );
    return Workstream.fromJson(response.data!);
  }

  Future<Workstream> update(
    String id, {
    String? name,
    String? code,
    String? description,
    String? imageUrl,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    bool? isActive,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/workstreams/$id',
        data: {
          'name': ?name,
          'code': ?code,
          'description': ?description,
          'imageUrl': ?imageUrl,
          'contactName': ?contactName,
          'contactEmail': ?contactEmail,
          'contactPhone': ?contactPhone,
          'isActive': ?isActive,
        },
      ),
    );
    return Workstream.fromJson(response.data!);
  }

  /// `DELETE /workstreams/:id` — soft-delete: flips `isActive` to false,
  /// never removes the row (categories keep a valid historical reference).
  Future<void> deactivate(String id) async {
    await _apiClient.guard((dio) => dio.delete('/workstreams/$id'));
  }

  Future<Workstream> reactivate(String id) => update(id, isActive: true);

  /// Uploads an image from device storage — `POST /workstreams/:id/image/
  /// upload` (multipart). Replaces any previously set URL or uploaded file.
  Future<Workstream> uploadImage(String id, {required Uint8List bytes, required String fileName}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/workstreams/$id/image/upload',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)}),
      ),
    );
    return Workstream.fromJson(response.data!);
  }

  /// Clears whichever image (URL or uploaded file) is currently set.
  Future<Workstream> removeImage(String id) async {
    final response = await _apiClient.guard((dio) => dio.delete<Map<String, dynamic>>('/workstreams/$id/image'));
    return Workstream.fromJson(response.data!);
  }

  /// Fetches an uploaded image's raw bytes (auth attached automatically by
  /// `ApiClient` — NOT a plain public URL `Image.network` could load).
  Future<Uint8List> getImageFileBytes(String id) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<int>>(
        '/workstreams/$id/image/file',
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(response.data!);
  }
}
