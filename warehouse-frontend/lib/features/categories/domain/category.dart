import '../../workstreams/domain/workstream.dart';

/// Mirrors the backend's `Category` model (`GET/POST/PATCH/DELETE
/// /categories`) — a self-referencing tree via `parentId`, soft-deleted via
/// `isActive` (never hard-deleted, per CLAUDE.md rule 10).
///
/// `workstreamId`: every category belongs to exactly ONE workstream (the
/// catalogue-organization layer — Warehouse -> Workstream -> Category ->
/// sub-category -> Product). A sub-category's workstream always matches its
/// parent's (backend-enforced); this is purely organizational, never read by
/// inventory/ledger code.
class Category {
  const Category({
    required this.id,
    required this.name,
    this.parentId,
    required this.workstreamId,
    this.workstream,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? parentId;
  final String workstreamId;
  final WorkstreamRef? workstream;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    workstreamId: json['workstreamId'] as String,
    workstream: json['workstream'] != null
        ? WorkstreamRef.fromJson(json['workstream'] as Map<String, dynamic>)
        : null,
    isActive: json['isActive'] as bool,
  );
}
