import 'permission.dart';

/// Mirrors `GET/POST/PATCH /roles` and `PUT /roles/:id/permissions`
/// (`RolesService`). `isSystem` roles (ADMIN/MANAGER/WAREHOUSE — seeded, see
/// `warehouse/prisma/seed.ts`) can't be renamed or deleted
/// (`RolesService.update`/`.remove`), though their PERMISSIONS can still be
/// reassigned. `remove` is a real hard delete, blocked (409) if the role is
/// still assigned to any user or is a system role.
class Role {
  const Role({
    required this.id,
    required this.name,
    this.description,
    required this.isSystem,
    required this.createdAt,
    required this.updatedAt,
    required this.permissions,
  });

  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Permission> permissions;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    isSystem: json['isSystem'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    permissions: (json['permissions'] as List<dynamic>)
        .map((e) => Permission.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
