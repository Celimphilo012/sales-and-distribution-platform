/// The fixed, backend-defined scope set an API key can hold
/// (`warehouse-node/src/core/scopes.js`'s `API_KEY_SCOPES`) — the external `/api/v1/*` boundary the back-office
/// consumes (ARCHITECTURE.md §A2's step-3 API-key mechanism).
const List<String> kApiKeyScopes = ['catalogue:read', 'stock:read', 'stock:reserve', 'stock:issue'];

/// Mirrors `GET/POST /api-keys`, `POST /api-keys/:id/revoke`
/// (`ApiKeysService`'s `KEY_SELECT`) — never the raw key itself; only
/// [ApiKeyCreated.rawKey] (the one-time create response) ever carries it.
class ApiKeyRecord {
  const ApiKeyRecord({
    required this.id,
    required this.name,
    required this.scopes,
    required this.isActive,
    required this.createdAt,
    this.lastUsedAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final List<String> scopes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  /// The creating user's id only (`ApiKeysService.KEY_SELECT` selects the
  /// scalar `createdBy` column, no `createdByUser` include) — resolved to a
  /// name client-side against the already-loaded users list when possible.
  final String createdBy;

  factory ApiKeyRecord.fromJson(Map<String, dynamic> json) => ApiKeyRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    scopes: (json['scopes'] as List<dynamic>).cast<String>(),
    isActive: json['isActive'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastUsedAt: json['lastUsedAt'] == null ? null : DateTime.parse(json['lastUsedAt'] as String),
    createdBy: json['createdBy'] as String,
  );
}

/// The one-time response to `POST /api-keys`: [record] plus [rawKey], which
/// the backend can never return again (only the argon2 hash is persisted).
/// Never stored beyond the create-response display — not logged, not cached
/// in any provider.
class ApiKeyCreated {
  const ApiKeyCreated({required this.record, required this.rawKey});

  final ApiKeyRecord record;
  final String rawKey;

  factory ApiKeyCreated.fromJson(Map<String, dynamic> json) =>
      ApiKeyCreated(record: ApiKeyRecord.fromJson(json), rawKey: json['rawKey'] as String);
}
