import '../../../core/network/api_client.dart';
import '../domain/audit_log.dart';
import '../domain/audit_log_query.dart';

/// `GET /audit-logs` (`AuditController`, gated `audit.view`) — confirmed
/// against the real `ListAuditLogsQueryDto`/`AuditService.findAll`. Unlike
/// the warehouse system, this endpoint is real: the ordering backend has had
/// a read side for `audit_logs` since step 1G.
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
