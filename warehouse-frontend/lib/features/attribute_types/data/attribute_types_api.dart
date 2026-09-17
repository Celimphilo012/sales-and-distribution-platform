import '../../../core/network/api_client.dart';
import '../domain/attribute_type.dart';

/// All attribute-type API calls (`GET/POST/PATCH/DELETE /attribute-types`).
/// Gated with the SAME permissions as categories/products/workstreams:
/// `catalogue.view` to read, `products.manage` to create/edit/deactivate.
class AttributeTypesApi {
  AttributeTypesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<AttributeType>> list({bool includeInactive = false}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/attribute-types',
        queryParameters: {if (includeInactive) 'includeInactive': true},
      ),
    );
    return response.data!.map((e) => AttributeType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AttributeType> create({
    required String name,
    required String code,
    AttributeDataType dataType = AttributeDataType.text,
    String? unit,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/attribute-types',
        data: {'name': name, 'code': code, 'dataType': dataType.toJson(), 'unit': ?unit},
      ),
    );
    return AttributeType.fromJson(response.data!);
  }

  Future<AttributeType> update(
    String id, {
    String? name,
    String? code,
    AttributeDataType? dataType,
    String? unit,
    bool? isActive,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/attribute-types/$id',
        data: {
          'name': ?name,
          'code': ?code,
          'dataType': ?dataType?.toJson(),
          'unit': ?unit,
          'isActive': ?isActive,
        },
      ),
    );
    return AttributeType.fromJson(response.data!);
  }

  /// `DELETE /attribute-types/:id` — soft-delete: flips `isActive` to
  /// false, never removes the row.
  Future<void> deactivate(String id) async {
    await _apiClient.guard((dio) => dio.delete('/attribute-types/$id'));
  }

  Future<AttributeType> reactivate(String id) => update(id, isActive: true);
}
