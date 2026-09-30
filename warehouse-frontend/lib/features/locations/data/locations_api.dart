import '../../../core/network/api_client.dart';
import '../domain/location.dart';

/// All location API calls (§G). Reads (`roots`/`subtree`/`getById`) require
/// `warehouse.structure.view`; mutations require `warehouse.structure.manage`
/// — split on the real backend after step 6c (see CLAUDE.md's "BACKEND GAP
/// fixed" note). `.manage` implies `.view` there (ADMIN holds both).
class LocationsApi {
  LocationsApi(this._apiClient);

  final ApiClient _apiClient;

  /// Top-level (`parentId IS NULL`) locations for one warehouse — a
  /// warehouse can have more than one root, so the structure view fetches
  /// these first, then the subtree of each (see [subtree]).
  Future<List<Location>> roots(String warehouseId, {bool includeInactive = false}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/locations',
        queryParameters: {
          'warehouseId': warehouseId,
          'rootOnly': true,
          if (includeInactive) 'includeInactive': true,
        },
      ),
    );
    return response.data!.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /locations/:id/subtree` — the real recursive-CTE read (§G): the
  /// root itself plus every descendant, each with a `depth` relative to
  /// THIS root. Unlimited depth, no schema/client limit.
  Future<List<Location>> subtree(String rootId, {bool includeInactive = false}) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>(
        '/locations/$rootId/subtree',
        queryParameters: {if (includeInactive) 'includeInactive': true},
      ),
    );
    return response.data!.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Location> getById(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/locations/$id'));
    return Location.fromJson(response.data!);
  }

  /// `POST /locations/:parentId/children` — create directly under an
  /// existing location (warehouse is inherited from the parent).
  Future<Location> addChild(
    String parentId, {
    required String name,
    required String code,
    required String locationType,
    String? description,
    int? capacity,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/locations/$parentId/children',
        data: {
          'name': name,
          'code': code,
          'locationType': locationType,
          if (description != null && description.isNotEmpty) 'description': description,
          'capacity': ?capacity,
        },
      ),
    );
    return Location.fromJson(response.data!);
  }

  /// `POST /locations` — create a warehouse-level root location (no
  /// parent), used only from the warehouse structure view's "add root
  /// location" action.
  Future<Location> createRoot(
    String warehouseId, {
    required String name,
    required String code,
    required String locationType,
    String? description,
    int? capacity,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/locations',
        data: {
          'warehouseId': warehouseId,
          'name': name,
          'code': code,
          'locationType': locationType,
          if (description != null && description.isNotEmpty) 'description': description,
          'capacity': ?capacity,
        },
      ),
    );
    return Location.fromJson(response.data!);
  }

  Future<Location> update(
    String id, {
    String? name,
    String? code,
    String? locationType,
    String? description,
    bool? isActive,
    int? capacity,
    bool clearCapacity = false,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/locations/$id',
        data: {
          'name': ?name,
          'code': ?code,
          'locationType': ?locationType,
          'description': ?description,
          'isActive': ?isActive,
          if (clearCapacity) 'capacity': null else 'capacity': ?capacity,
        },
      ),
    );
    return Location.fromJson(response.data!);
  }

  /// `POST /locations/:id/move` — reparent (moves the whole subtree with
  /// it, since children just keep pointing at the same `parentId`).
  /// `newParentId: null` moves it to the root of its own warehouse. The
  /// backend rejects a self-parent (400), a cycle (409), and a cross-
  /// warehouse move (400) — this method doesn't pre-validate those beyond
  /// what the caller already excluded from the picker; errors surface via
  /// the normal `AppError` mapping.
  Future<Location> move(String id, {required String? newParentId}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/locations/$id/move', data: {'parentId': newParentId}),
    );
    return Location.fromJson(response.data!);
  }

  /// `DELETE /locations/:id` — soft-delete. The real backend does NOT
  /// check for active children before deactivating (confirmed against
  /// `LocationsService.remove`) — it simply flips this one row's
  /// `isActive`, leaving any children untouched (still active, now sitting
  /// under an inactive parent). No cascade, no block.
  Future<void> deactivate(String id) async {
    await _apiClient.guard((dio) => dio.delete('/locations/$id'));
  }

  Future<Location> reactivate(String id) => update(id, isActive: true);

  /// `POST /locations/:parentId/levels` — the "create N levels" convenience
  /// (§G: "no schema limit... admins can still add/remove levels ...
  /// afterwards"). Deliberately no upper bound on `count` here either —
  /// this is a thin pass-through to the backend's own unbounded loop.
  Future<List<Location>> generateLevels(
    String parentId, {
    required int count,
    String? locationType,
    String? namePrefix,
    String? codePrefix,
    int? startIndex,
    int? capacity,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<List<dynamic>>(
        '/locations/$parentId/levels',
        data: {
          'count': count,
          'locationType': ?locationType,
          'namePrefix': ?namePrefix,
          'codePrefix': ?codePrefix,
          'startIndex': ?startIndex,
          'capacity': ?capacity,
        },
      ),
    );
    return response.data!.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
  }
}
