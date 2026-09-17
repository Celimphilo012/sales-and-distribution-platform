import '../../../core/network/api_client.dart';
import '../domain/category.dart';

/// All category API calls (`GET/POST/PATCH/DELETE /categories`).
class CategoriesApi {
  CategoriesApi(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /categories` is a FLAT list, not a tree — there's no recursive
  /// endpoint like `/locations/:id/subtree`. Fetching with no `parentId`
  /// filter returns every category regardless of depth; the tree is built
  /// client-side (see `domain/category_tree.dart`).
  Future<List<Category>> list({bool includeInactive = false, String? workstreamId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/categories',
        queryParameters: {
          if (includeInactive) 'includeInactive': true,
          'workstreamId': ?workstreamId,
        },
      ),
    );
    return response.data!.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Category> create({required String name, required String workstreamId, String? parentId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/categories',
        data: {'name': name, 'workstreamId': workstreamId, 'parentId': ?parentId},
      ),
    );
    return Category.fromJson(response.data!);
  }

  /// `parentId: null` moves the category to root; omitting it (the default)
  /// leaves the parent untouched — matches `UpdateCategoryDto` exactly.
  Future<Category> update(
    String id, {
    String? name,
    Object? parentId = _unset,
    String? workstreamId,
    bool? isActive,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/categories/$id',
        data: {
          'name': ?name,
          if (!identical(parentId, _unset)) 'parentId': parentId,
          'workstreamId': ?workstreamId,
          'isActive': ?isActive,
        },
      ),
    );
    return Category.fromJson(response.data!);
  }

  /// `DELETE /categories/:id` — soft-delete: flips `isActive` to false,
  /// never removes the row (products keep a valid historical reference).
  Future<void> deactivate(String id) async {
    await _apiClient.guard((dio) => dio.delete('/categories/$id'));
  }
}

const _unset = Object();
