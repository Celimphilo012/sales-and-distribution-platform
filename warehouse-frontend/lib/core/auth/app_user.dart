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
/// Permission strings mirror the WAREHOUSE backend's permission catalog
/// (`warehouse-node/src/catalog/permission-catalog.js`) — the front
/// end never checks a role name, only permission strings, per CLAUDE.md
/// rule 1. This app is a standalone client of /warehouse-node only; it never
/// sees ordering-side permissions like `orders.*`/`customers.*`.
///
/// [roles] and [status] mirror the extra fields `GET /auth/me` returns
/// alongside `permissions` (step 6f) — used by the Settings > Profile screen
/// so it can show "who am I" without a second network call.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.permissions,
    this.roles = const [],
    this.status,
    this.phone,
    this.notifyChannel = 'EMAIL',
    this.mfaMethod = 'NONE',
  });

  final String id;
  final String name;
  final String email;
  final Set<String> permissions;
  final List<AppUserRoleRef> roles;
  final String? status;

  /// International format (+268…), or null. Needed for SMS codes/notifications.
  final String? phone;

  /// How approval notifications reach this user: `EMAIL`, `SMS` or `NONE`.
  final String notifyChannel;

  /// Sign-in verification: `NONE`, `EMAIL`, `SMS` or `TOTP` (authenticator app).
  final String mfaMethod;

  bool can(String permission) => permissions.contains(permission);

  /// True if the user holds any of [permissions] — useful for nav sections
  /// that unlock under more than one permission key.
  bool canAny(Iterable<String> permissions) => permissions.any(can);
}
