/// The `{id, name}` the backend embeds on `/auth/me`'s `roles` array — same
/// flat shape as the `users`/`roles` admin screens' own role refs.
class AppUserRoleRef {
  const AppUserRoleRef({required this.id, required this.name});

  final String id;
  final String name;

  factory AppUserRoleRef.fromJson(Map<String, dynamic> json) =>
      AppUserRoleRef(id: json['id'] as String, name: json['name'] as String);
}

/// The signed-in user's identity and permission set.
///
/// Permission strings mirror the backend's permission catalog
/// (`ordering-backend/src/catalog/permission-catalog.js`) — the front
/// end never checks a role name, only permission strings, per CLAUDE.md
/// rule 1. This app is a standalone client of `/ordering-backend` only; it never sees
/// warehouse-side permissions like `catalogue.view`/`inventory.*`/
/// `warehouse.structure.*`.
///
/// [roles] and [status] mirror the extra fields `GET /auth/me` returns
/// alongside `permissions` (step R1, brought over from the warehouse app's
/// step 6f) — used by the Settings > Profile screen so it can show "who am
/// I" without a second network call.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.permissions,
    this.roles = const [],
    this.status,
  });

  final String id;
  final String name;
  final String email;
  final Set<String> permissions;
  final List<AppUserRoleRef> roles;
  final String? status;

  bool can(String permission) => permissions.contains(permission);

  /// True if the user holds any of [permissions] — useful for nav sections
  /// that unlock under more than one permission key.
  bool canAny(Iterable<String> permissions) => permissions.any(can);
}
