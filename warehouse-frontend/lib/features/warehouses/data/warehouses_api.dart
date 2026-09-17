import '../../../core/network/api_client.dart';
import '../domain/warehouse.dart';

/// All warehouse API calls (`GET/POST/PATCH/DELETE /warehouses`). The reads
/// (`list`/`getById`) require `warehouse.structure.view`; the mutations
/// require `warehouse.structure.manage` — split on the real backend after
/// step 6c (see CLAUDE.md's "BACKEND GAP fixed" note). `.manage` implies
/// `.view` there (ADMIN holds both).
class WarehousesApi {
  WarehousesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Warehouse>> list({bool includeInactive = false}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/warehouses',
        queryParameters: {if (includeInactive) 'includeInactive': true},
      ),
    );
    return response.data!.map((e) => Warehouse.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Warehouse> getById(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/warehouses/$id'));
    return Warehouse.fromJson(response.data!);
  }

  Future<Warehouse> create({required String name, required String code}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/warehouses', data: {'name': name, 'code': code}),
    );
    return Warehouse.fromJson(response.data!);
  }

  Future<Warehouse> update(String id, {String? name, String? code, bool? isActive}) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/warehouses/$id',
        data: {'name': ?name, 'code': ?code, 'isActive': ?isActive},
      ),
    );
    return Warehouse.fromJson(response.data!);
  }

  /// `DELETE /warehouses/:id` — soft-delete: flips `isActive` to false,
  /// never removes the row.
  Future<void> deactivate(String id) async {
    await _apiClient.guard((dio) => dio.delete('/warehouses/$id'));
  }

  Future<Warehouse> reactivate(String id) => update(id, isActive: true);
}
