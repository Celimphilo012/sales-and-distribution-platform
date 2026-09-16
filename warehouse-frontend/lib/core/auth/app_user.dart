/// The signed-in user's identity and permission set.
///
/// Permission strings mirror the WAREHOUSE backend's permission catalog
/// (`warehouse/src/permissions/constants/permission-catalog.ts`) — the front
/// end never checks a role name, only permission strings, per CLAUDE.md
/// rule 1. This app is a standalone client of /warehouse only; it never
/// sees ordering-side permissions like `orders.*`/`customers.*`.
class AppUser {
  const AppUser({required this.id, required this.name, required this.email, required this.permissions});

  final String id;
  final String name;
  final String email;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  /// True if the user holds any of [permissions] — useful for nav sections
  /// that unlock under more than one permission key.
  bool canAny(Iterable<String> permissions) => permissions.any(can);
}
