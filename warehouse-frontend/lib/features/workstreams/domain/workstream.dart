import '../../../shared/json_utils.dart';

/// Mirrors the backend's `Workstream` model (`GET/POST/PATCH/DELETE
/// /workstreams`) — a catalogue-organization layer, NOT operational: it sits
/// between Warehouse and Category (Warehouse -> Workstream -> Category ->
/// sub-category -> Product) but never affects inventory/stock/permissions/
/// fulfilment. A workstream belongs to exactly one warehouse.
class Workstream {
  const Workstream({
    required this.id,
    required this.warehouseId,
    required this.name,
    required this.code,
    this.description,
    this.imageUrl,
    this.hasImageFile = false,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    required this.isActive,
  });

  final String id;
  final String warehouseId;
  final String name;
  final String code;
  final String? description;

  /// An external link, rendered directly — mutually exclusive with
  /// [hasImageFile] (see `Workstream.imagePath` on the backend).
  final String? imageUrl;

  /// True when a file was uploaded from device storage instead — fetched via
  /// the authenticated `GET /workstreams/:id/image/file` endpoint, not a
  /// directly-reachable URL.
  final bool hasImageFile;

  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;

  final bool isActive;

  bool get hasImage => imageUrl != null || hasImageFile;

  /// Whether there's any contact info at all worth showing.
  bool get hasContactInfo => contactName != null || contactEmail != null || contactPhone != null;

  factory Workstream.fromJson(Map<String, dynamic> json) => Workstream(
    id: json['id'] as String,
    warehouseId: json['warehouseId'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    hasImageFile: json['imagePath'] != null,
    contactName: json['contactName'] as String?,
    contactEmail: json['contactEmail'] as String?,
    contactPhone: json['contactPhone'] as String?,
    isActive: boolFromJson(json['isActive']),
  );
}

/// The `{id, name, code}` the backend embeds on a category (and, nested, on
/// a product's category) for its workstream — not the full [Workstream].
class WorkstreamRef {
  const WorkstreamRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory WorkstreamRef.fromJson(Map<String, dynamic> json) =>
      WorkstreamRef(id: json['id'] as String, name: json['name'] as String, code: json['code'] as String);
}
