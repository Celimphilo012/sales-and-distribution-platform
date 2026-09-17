/// Mirrors `GET /permissions` (`PermissionsService.findAll` — the full,
/// flat permission catalog, ordered by module then key). A role is a bag of
/// these (§F) — permissions are never hard-coded into UI `if`s (rule 1).
class Permission {
  const Permission({required this.id, required this.key, this.description, this.module});

  final String id;
  final String key;
  final String? description;
  final String? module;

  factory Permission.fromJson(Map<String, dynamic> json) => Permission(
    id: json['id'] as String,
    key: json['key'] as String,
    description: json['description'] as String?,
    module: json['module'] as String?,
  );
}
