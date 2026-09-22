import '../../../core/network/api_client.dart';
import '../domain/audit_log.dart';
import '../domain/audit_log_query.dart';

/// `GET /audit-logs` (`AuditController`, gated `audit.view`) — added to the
/// warehouse backend to close the gap `AuditLogScreen` used to report (see
/// CLAUDE.md history): the interceptor always wrote `audit_logs`, there was
/// just no controller reading it back until now.
class AuditLogsApi {
  AuditLogsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<AuditLogPage> list(AuditLogQuery query) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/audit-logs', queryParameters: query.toQueryParameters()),
    );
    return AuditLogPage.fromJson(response.data!);
  }
}
