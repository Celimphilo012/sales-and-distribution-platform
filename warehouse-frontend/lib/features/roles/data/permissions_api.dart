import '../../../core/network/api_client.dart';
import '../domain/permission.dart';

/// `GET /permissions` — the full permission catalog (`PermissionsController`,
/// gated `roles.manage`, same as the rest of the RBAC admin surface).
class PermissionsApi {
  PermissionsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Permission>> list() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/permissions'));
    return response.data!.map((e) => Permission.fromJson(e as Map<String, dynamic>)).toList();
  }
}
