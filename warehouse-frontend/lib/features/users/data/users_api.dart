import '../../../core/network/api_client.dart';
import '../domain/user.dart';

/// `GET/POST/PATCH/DELETE /users` (`UsersController`, gated `users.manage`
/// except `GET /users/me`, which any authenticated user may call). Confirmed
/// against the real controller/DTOs — no surprises from the spec's assumed
/// shape.
class UsersApi {
  UsersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<WarehouseUser>> list() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/users'));
    return response.data!.map((e) => WarehouseUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WarehouseUser> getOne(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/users/$id'));
    return WarehouseUser.fromJson(response.data!);
  }

  Future<WarehouseUser> create({
    required String email,
    required String password,
    required String fullName,
    List<String>? roleIds,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/users',
        data: {'email': email, 'password': password, 'fullName': fullName, 'roleIds': ?roleIds},
      ),
    );
    return WarehouseUser.fromJson(response.data!);
  }

  /// [roleIds], when supplied, REPLACES the user's full role set — omit it
  /// to leave roles untouched (`UpdateUserDto.roleIds` is optional).
  Future<WarehouseUser> update(
    String id, {
    String? fullName,
    String? password,
    UserStatus? status,
    List<String>? roleIds,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/users/$id',
        data: {
          'fullName': ?fullName,
          'password': ?password,
          'status': ?status?.apiValue,
          'roleIds': ?roleIds,
        },
      ),
    );
    return WarehouseUser.fromJson(response.data!);
  }

  /// `DELETE /users/:id` — soft-deactivates (sets `status: INACTIVE`), never
  /// a hard delete (`UsersService.remove`).
  Future<WarehouseUser> deactivate(String id) async {
    final response = await _apiClient.guard((dio) => dio.delete<Map<String, dynamic>>('/users/$id'));
    return WarehouseUser.fromJson(response.data!);
  }
}
