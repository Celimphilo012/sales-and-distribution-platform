/// Filter + pagination state for `GET /audit-logs`, mirroring
/// `ListAuditLogsQueryDto` field-for-field. Immutable — the screen holds one
/// in a Riverpod `Notifier` and calls [copyWith] to change a field, same
/// pattern as `ProductsFilter`.
class AuditLogQuery {
  const AuditLogQuery({
    this.userId,
    this.entity,
    this.entityId,
    this.action,
    this.from,
    this.to,
    this.page = 1,
    this.pageSize = 20,
  });

  final String? userId;
  final String? entity;
  final String? entityId;
  final String? action;
  final DateTime? from;
  final DateTime? to;
  final int page;
  final int pageSize;

  AuditLogQuery copyWith({
    String? userId,
    bool clearUserId = false,
    String? entity,
    bool clearEntity = false,
    String? entityId,
    bool clearEntityId = false,
    String? action,
    bool clearAction = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? page,
    int? pageSize,
  }) {
    return AuditLogQuery(
      userId: clearUserId ? null : (userId ?? this.userId),
      entity: clearEntity ? null : (entity ?? this.entity),
      entityId: clearEntityId ? null : (entityId ?? this.entityId),
      action: clearAction ? null : (action ?? this.action),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() => {
    'userId': ?userId,
    'entity': ?entity,
    'entityId': ?entityId,
    'action': ?action,
    'from': ?from?.toUtc().toIso8601String(),
    'to': ?to?.toUtc().toIso8601String(),
    'page': page,
    'pageSize': pageSize,
  };

  @override
  bool operator ==(Object other) =>
      other is AuditLogQuery &&
      other.userId == userId &&
      other.entity == entity &&
      other.entityId == entityId &&
      other.action == action &&
      other.from == from &&
      other.to == to &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(userId, entity, entityId, action, from, to, page, pageSize);
}
