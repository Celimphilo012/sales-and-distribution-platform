/// Mirrors the backend's `users.status` enum (`ordering-backend/db/schema.sql`)
/// — three states, not just active/inactive. `remove` (`DELETE /users/:id`)
/// only ever sets INACTIVE; SUSPENDED is reachable via `PATCH /users/:id`'s
/// `status` field.
enum UserStatus { active, inactive, suspended }

UserStatus userStatusFromJson(String value) => switch (value) {
  'ACTIVE' => UserStatus.active,
  'INACTIVE' => UserStatus.inactive,
  'SUSPENDED' => UserStatus.suspended,
  _ => throw ArgumentError('Unknown user status: $value'),
};

extension UserStatusX on UserStatus {
  String get apiValue => switch (this) {
    UserStatus.active => 'ACTIVE',
    UserStatus.inactive => 'INACTIVE',
    UserStatus.suspended => 'SUSPENDED',
  };

  String get label => switch (this) {
    UserStatus.active => 'Active',
    UserStatus.inactive => 'Inactive',
    UserStatus.suspended => 'Suspended',
  };
}

/// The `{id, name}` the backend embeds on a user for each assigned role
/// (`UsersService`'s `present()` — `USER_SELECT`'s `userRoles.role`).
class WarehouseUserRoleRef {
  const WarehouseUserRoleRef({required this.id, required this.name});

  final String id;
  final String name;

  factory WarehouseUserRoleRef.fromJson(Map<String, dynamic> json) =>
      WarehouseUserRoleRef(id: json['id'] as String, name: json['name'] as String);
}

/// Mirrors `GET/POST/PATCH/DELETE /users` (`UsersService`). `roleIds` on
/// write is a FULL REPLACE of the user's role set (`UpdateUserDto.roleIds` /
/// `CreateUserDto.roleIds`) — there is no separate assign/unassign-one-role
/// endpoint, matching how `AssignPermissionsDto` works for roles↔permissions.
/// `DELETE` never hard-deletes — it sets `status: INACTIVE` (rule 10:
/// soft-delete reference data; historical `audit_logs`/ledger rows keep a
/// valid `performed_by`/`requested_by` author).
class WarehouseUser {
  const WarehouseUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.roles,
  });

  final String id;
  final String email;
  final String fullName;
  final UserStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WarehouseUserRoleRef> roles;

  factory WarehouseUser.fromJson(Map<String, dynamic> json) => WarehouseUser(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['fullName'] as String,
    status: userStatusFromJson(json['status'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    roles: (json['roles'] as List<dynamic>)
        .map((e) => WarehouseUserRoleRef.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
