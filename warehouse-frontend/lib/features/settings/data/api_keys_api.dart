import '../../../core/network/api_client.dart';
import '../domain/api_key.dart';

/// `GET/POST /api-keys`, `POST /api-keys/:id/revoke` (`ApiKeysController`,
/// gated `users.manage` — the step-3 brief's choice, reused rather than a
/// new permission key). Warehouse-specific: the ordering app never issues
/// these, so unlike Users/Roles/Audit this one isn't meant to be copied
/// there.
class ApiKeysApi {
  ApiKeysApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ApiKeyRecord>> list() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/api-keys'));
    return response.data!.map((e) => ApiKeyRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns the raw key ONCE — see [ApiKeyCreated].
  Future<ApiKeyCreated> create({required String name, required List<String> scopes}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/api-keys', data: {'name': name, 'scopes': scopes}),
    );
    return ApiKeyCreated.fromJson(response.data!);
  }

  Future<ApiKeyRecord> revoke(String id) async {
    final response = await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/api-keys/$id/revoke'));
    return ApiKeyRecord.fromJson(response.data!);
  }
}
