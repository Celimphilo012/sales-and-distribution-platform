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
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/workstreams',
        data: {'warehouseId': warehouseId, 'name': name, 'code': code, 'description': ?description},
      ),
    );
    return Workstream.fromJson(response.data!);
  }

  Future<Workstream> update(
    String id, {
    String? name,
    String? code,
    String? description,
    bool? isActive,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/workstreams/$id',
        data: {'name': ?name, 'code': ?code, 'description': ?description, 'isActive': ?isActive},
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
}
