/// Mirrors the backend's `UserStatus` enum (`warehouse/prisma/schema.prisma`)
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

/// A warehouse a user is assigned to (access is deny-by-default: a user sees
/// only the warehouses listed here, unless they hold `warehouse.access.all`).
class UserWarehouseRef {
  const UserWarehouseRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory UserWarehouseRef.fromJson(Map<String, dynamic> json) =>
      UserWarehouseRef(id: json['id'] as String, name: json['name'] as String, code: json['code'] as String);
}

/// How a user receives approval notifications / default one-time codes.
const Map<String, String> kNotifyChannelLabels = {'EMAIL': 'Email', 'SMS': 'SMS', 'NONE': 'Off'};

/// Sign-in verification methods.
const Map<String, String> kMfaMethodLabels = {
  'NONE': 'Off',
  'EMAIL': 'Email code',
  'SMS': 'SMS code',
  'TOTP': 'Authenticator app',
};

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
    this.phone,
    this.notifyChannel = 'EMAIL',
    this.mfaMethod = 'NONE',
    this.warehouses = const [],
  });

  final String id;
  final String email;
  final String fullName;
  final UserStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WarehouseUserRoleRef> roles;
  final String? phone;
  final String notifyChannel;
  final String mfaMethod;
  final List<UserWarehouseRef> warehouses;

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
    phone: json['phone'] as String?,
    notifyChannel: json['notifyChannel'] as String? ?? 'EMAIL',
    mfaMethod: json['mfaMethod'] as String? ?? 'NONE',
    warehouses: (json['warehouses'] as List<dynamic>? ?? const [])
        .map((e) => UserWarehouseRef.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
