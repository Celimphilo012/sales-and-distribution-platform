import '../../../core/network/api_client.dart';
import '../domain/dashboard_summary.dart';

/// `GET /dashboard` (`DashboardController`, gated `reports.view`) — one
/// aggregated read for the homepage summary screen.
class DashboardApi {
  DashboardApi(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardSummary> get() async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/dashboard'));
    return DashboardSummary.fromJson(response.data!);
  }
}
