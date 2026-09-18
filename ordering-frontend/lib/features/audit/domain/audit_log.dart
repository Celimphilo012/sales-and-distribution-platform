/// The `{id, fullName, email}` the backend embeds on an audit log row for
/// its actor (`AuditService.findAll`'s `include: { user: {...} }`). Null
/// when the row's `userId` itself is null (a system action with no
/// authenticated user — rare on this system, unlike the warehouse's
/// API-key-attributed rows).
class AuditLogUserRef {
  const AuditLogUserRef({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  factory AuditLogUserRef.fromJson(Map<String, dynamic> json) => AuditLogUserRef(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    email: json['email'] as String,
  );
}

/// Mirrors one row of `GET /audit-logs` (`AuditController`/`AuditService`,
/// gated `audit.view`) — one row per successful mutating request, written by
/// the global `AuditInterceptor`. Unlike the warehouse system (which has no
/// read endpoint for this table — see CLAUDE.md), the ordering backend has
/// had one since step 1G, so this screen shows real data.
class AuditLog {
  const AuditLog({
    required this.id,
    this.userId,
    this.user,
    required this.action,
    required this.entity,
    this.entityId,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final AuditLogUserRef? user;
  final String action;
  final String entity;
  final String? entityId;
  final Object? oldValue;
  final Object? newValue;
  final DateTime createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as String,
    userId: json['userId'] as String?,
    user: json['user'] == null ? null : AuditLogUserRef.fromJson(json['user'] as Map<String, dynamic>),
    action: json['action'] as String,
    entity: json['entity'] as String,
    entityId: json['entityId'] as String?,
    oldValue: json['oldValue'],
    newValue: json['newValue'],
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// The paginated envelope `AuditService.findAll` returns —
/// `{data, page, pageSize, total, totalPages}`.
class AuditLogPage {
  const AuditLogPage({
    required this.data,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  final List<AuditLog> data;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  factory AuditLogPage.fromJson(Map<String, dynamic> json) => AuditLogPage(
    data: (json['data'] as List<dynamic>).map((e) => AuditLog.fromJson(e as Map<String, dynamic>)).toList(),
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
    total: json['total'] as int,
    totalPages: json['totalPages'] as int,
  );
}
