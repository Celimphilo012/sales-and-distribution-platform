import '../../../shared/json_utils.dart';

/// Mirrors the backend's `Location` model (§G — self-referencing tree via
/// `parentId`, unlimited depth, soft-deleted via `isActive`).
/// `locationType` is a free-form label, never a structural constraint —
/// this app never validates it against a fixed enum (see `location_types.dart`
/// for the SUGGESTED labels only).
///
/// [depth] is only present when this location came back from
/// `GET /locations/:id/subtree` (0 = the subtree's root); everywhere else
/// it's null.
class Location {
  const Location({
    required this.id,
    required this.warehouseId,
    this.parentId,
    required this.name,
    required this.code,
    required this.locationType,
    this.description,
    this.capacity,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.depth,
  });

  final String id;
  final String warehouseId;
  final String? parentId;
  final String name;
  final String code;
  final String locationType;
  final String? description;

  /// Units this location holds when full (usually set on storage slots) —
  /// the fill / utilisation bars. Null = not set.
  final int? capacity;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? depth;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'] as String,
    warehouseId: json['warehouseId'] as String,
    parentId: json['parentId'] as String?,
    name: json['name'] as String,
    code: json['code'] as String,
    locationType: json['locationType'] as String,
    description: json['description'] as String?,
    capacity: json['capacity'] == null ? null : (json['capacity'] as num).toInt(),
    isActive: boolFromJson(json['isActive']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    depth: json['depth'] == null ? null : (json['depth'] as num).toInt(),
  );
}
