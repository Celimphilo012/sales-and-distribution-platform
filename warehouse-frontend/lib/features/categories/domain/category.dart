/// Mirrors the backend's `Category` model (`GET/POST/PATCH/DELETE
/// /categories`) — a self-referencing tree via `parentId`, soft-deleted via
/// `isActive` (never hard-deleted, per CLAUDE.md rule 10).
class Category {
  const Category({required this.id, required this.name, this.parentId, required this.isActive});

  final String id;
  final String name;
  final String? parentId;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    isActive: json['isActive'] as bool,
  );
}
