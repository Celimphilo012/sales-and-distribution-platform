/// Mirrors the backend's `AuditLog` model (`warehouse/prisma/schema.prisma`)
/// — one row per successful mutating request, written by the global
/// `AuditInterceptor`. There is currently NO read endpoint for this table
/// (see `AuditLogScreen`'s backend-gap notice) — this model exists so the
/// shape is ready to deserialize against the moment one exists, on this app
/// or the ordering app's near-identical audit log.
class AuditLog {
  const AuditLog({
    required this.id,
    this.userId,
    this.apiKeyId,
    required this.action,
    required this.entity,
    this.entityId,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  final String id;

  /// Null when an API key (not a logged-in user) performed the request —
  /// the two are mutually exclusive (see [apiKeyId]).
  final String? userId;
  final String? apiKeyId;
  final String action;
  final String entity;
  final String? entityId;
  final Object? oldValue;
  final Object? newValue;
  final DateTime createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as String,
    userId: json['userId'] as String?,
    apiKeyId: json['apiKeyId'] as String?,
    action: json['action'] as String,
    entity: json['entity'] as String,
    entityId: json['entityId'] as String?,
    oldValue: json['oldValue'],
    newValue: json['newValue'],
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
