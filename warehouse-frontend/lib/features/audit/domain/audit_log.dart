/// The `{id, fullName, email}` the backend embeds on an audit log row for
/// its actor (`AuditService.findAll`'s `include: { user: {...} }`). Null
/// when the row was performed by an API key instead — see [AuditLogApiKeyRef].
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

/// The `{id, name}` the backend embeds for a row performed by an external API
/// key rather than a logged-in user (`AuditService.findAll`'s
/// `include: { apiKey: {...} }`) — the warehouse's external API is
/// key-authenticated (see `ApiKeyGuard`), unlike the ordering app, so this
/// case doesn't exist on that app's near-identical audit log.
class AuditLogApiKeyRef {
  const AuditLogApiKeyRef({required this.id, required this.name});

  final String id;
  final String name;

  factory AuditLogApiKeyRef.fromJson(Map<String, dynamic> json) =>
      AuditLogApiKeyRef(id: json['id'] as String, name: json['name'] as String);
}

/// Mirrors one row of `GET /audit-logs` (`AuditController`/`AuditService`,
/// gated `audit.view`) — one row per successful mutating request, written by
/// the global `AuditInterceptor`. [user] and [apiKey] are mutually exclusive:
/// a request is authenticated by exactly one of a logged-in user's JWT or an
/// external caller's API key.
class AuditLog {
  const AuditLog({
    required this.id,
    this.userId,
    this.user,
    this.apiKeyId,
    this.apiKey,
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
  final String? apiKeyId;
  final AuditLogApiKeyRef? apiKey;
  final String action;
  final String entity;
  final String? entityId;
  final Object? oldValue;
  final Object? newValue;
  final DateTime createdAt;

  /// "Who did this" for display — a user's name, an API key's name, or an
  /// em dash if somehow neither is set (shouldn't happen, but never crash a
  /// list screen over it).
  String get actorLabel => user?.fullName ?? (apiKey != null ? '${apiKey!.name} (API key)' : '—');

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as String,
    userId: json['userId'] as String?,
    user: json['user'] == null ? null : AuditLogUserRef.fromJson(json['user'] as Map<String, dynamic>),
    apiKeyId: json['apiKeyId'] as String?,
    apiKey: json['apiKey'] == null ? null : AuditLogApiKeyRef.fromJson(json['apiKey'] as Map<String, dynamic>),
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
