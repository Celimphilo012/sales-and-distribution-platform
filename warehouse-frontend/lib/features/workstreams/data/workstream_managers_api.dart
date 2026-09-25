import '../../../core/network/api_client.dart';
import '../domain/workstream_manager.dart';

/// `GET/POST /workstreams/:id/managers`, `DELETE /workstreams/:id/managers/
/// :userId` (gated `workstreams.assign`) and `GET /users/me/workstreams`
/// (self-service, no permission needed) — confirmed against
/// `WorkstreamManagersController`/`MyWorkstreamsController`.
class WorkstreamManagersApi {
  WorkstreamManagersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<WorkstreamManager>> listForWorkstream(String workstreamId) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>('/workstreams/$workstreamId/managers'),
    );
    return response.data!.map((e) => WorkstreamManager.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WorkstreamManager> assign(String workstreamId, String userId) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/workstreams/$workstreamId/managers', data: {'userId': userId}),
    );
    return WorkstreamManager.fromJson(response.data!);
  }

  Future<void> unassign(String workstreamId, String userId) async {
    await _apiClient.guard((dio) => dio.delete('/workstreams/$workstreamId/managers/$userId'));
  }

  /// "Which workstreams am I scoped to?" — an empty list means unscoped
  /// (today's global behaviour), same convention as the backend.
  Future<List<MyWorkstreamAssignment>> listMine() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/users/me/workstreams'));
    return response.data!.map((e) => MyWorkstreamAssignment.fromJson(e as Map<String, dynamic>)).toList();
  }
}
