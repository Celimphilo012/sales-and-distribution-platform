import '../../../core/network/api_client.dart';
import '../domain/role.dart';

/// `GET/POST/PATCH/DELETE /roles`, `PUT /roles/:id/permissions`
/// (`RolesController`, class-level gated `roles.manage` — no separate
/// read-only permission for this resource).
class RolesApi {
  RolesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Role>> list() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/roles'));
    return response.data!.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Role> getOne(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/roles/$id'));
    return Role.fromJson(response.data!);
  }

  Future<Role> create({required String name, String? description}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/roles', data: {'name': name, 'description': ?description}),
    );
    return Role.fromJson(response.data!);
  }

  Future<Role> update(String id, {String? name, String? description}) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/roles/$id',
        data: {'name': ?name, 'description': ?description},
      ),
    );
    return Role.fromJson(response.data!);
  }

  /// Replaces the role's FULL permission set — there is no
  /// assign/unassign-one endpoint (`AssignPermissionsDto.permissionIds`).
  Future<Role> assignPermissions(String id, {required List<String> permissionIds}) async {
    final response = await _apiClient.guard(
      (dio) => dio.put<Map<String, dynamic>>('/roles/$id/permissions', data: {'permissionIds': permissionIds}),
    );
    return Role.fromJson(response.data!);
  }

  /// A real hard delete — the backend 409s if the role is `isSystem` or
  /// still assigned to any user (`RolesService.remove`).
  Future<void> remove(String id) async {
    await _apiClient.guard((dio) => dio.delete('/roles/$id'));
  }
}
