/// A warehouse, as relayed by `GET /warehouse-locations` (`/backend`'s
/// JWT-guarded view over the warehouse's `/api/v1/locations`).
class WarehouseRef {
  const WarehouseRef({required this.id, required this.name, required this.code, required this.isActive});

  final String id;
  final String name;
  final String code;
  final bool isActive;

  factory WarehouseRef.fromJson(Map<String, dynamic> json) => WarehouseRef(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    isActive: json['isActive'] as bool? ?? true,
  );
}

/// One node of the warehouse's location tree (flat, `parentId`-linked —
/// unlimited depth, CLAUDE.md rule 5; no ancestor chain in the payload).
class WarehouseLocation {
  const WarehouseLocation({
    required this.id,
    required this.warehouseId,
    required this.parentId,
    required this.name,
    required this.code,
    required this.locationType,
    required this.isActive,
  });

  final String id;
  final String warehouseId;
  final String? parentId;
  final String name;
  final String code;
  final String locationType;
  final bool isActive;

  factory WarehouseLocation.fromJson(Map<String, dynamic> json) => WarehouseLocation(
    id: json['id'] as String,
    warehouseId: json['warehouseId'] as String,
    parentId: json['parentId'] as String?,
    name: json['name'] as String,
    code: json['code'] as String,
    locationType: json['locationType'] as String? ?? '',
    isActive: json['isActive'] as bool? ?? true,
  );
}

/// The whole location tree plus helpers the reserve picker needs.
class WarehouseLocations {
  WarehouseLocations({required this.warehouses, required this.locations})
    : _byId = {for (final l in locations) l.id: l},
      _warehouseById = {for (final w in warehouses) w.id: w};

  final List<WarehouseRef> warehouses;
  final List<WarehouseLocation> locations;
  final Map<String, WarehouseLocation> _byId;
  final Map<String, WarehouseRef> _warehouseById;

  factory WarehouseLocations.fromJson(Map<String, dynamic> json) => WarehouseLocations(
    warehouses: (json['warehouses'] as List<dynamic>)
        .map((e) => WarehouseRef.fromJson(e as Map<String, dynamic>))
        .toList(),
    locations: (json['locations'] as List<dynamic>)
        .map((e) => WarehouseLocation.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  WarehouseLocation? byId(String id) => _byId[id];

  /// Active locations that have no active child — the only places stock can
  /// live (leaf-only stock rule), so the only valid reserve targets — and
  /// that belong to a KNOWN, active warehouse. (The relay also carries
  /// locations of deactivated warehouses; those must not be offered.)
  List<WarehouseLocation> get leafLocations {
    final parentIds = {
      for (final l in locations)
        if (l.isActive && l.parentId != null) l.parentId!,
    };
    return [
      for (final l in locations)
        if (l.isActive && !parentIds.contains(l.id) && (_warehouseById[l.warehouseId]?.isActive ?? false)) l,
    ]..sort((a, b) => pathLabel(a.id).compareTo(pathLabel(b.id)));
  }

  /// The location's own "Name (CODE)" — what tells one leaf from another.
  String leafLabel(WarehouseLocation location) => '${location.name} (${location.code})';

  /// Where [locationId] sits, WITHOUT the location itself: "Warehouse › Zone
  /// › Rack". Empty for a top-level location with no known warehouse.
  String parentPathLabel(String locationId) {
    final full = pathLabel(locationId);
    final leaf = _byId[locationId]?.name;
    if (leaf == null || !full.endsWith(leaf)) return '';
    final cut = full.length - leaf.length;
    return full.substring(0, cut).replaceFirst(RegExp(r'\s*›\s*$'), '');
  }

  /// "Warehouse › Zone › Shelf › Bin" for [locationId] (falls back to the
  /// raw id if the location isn't in the loaded tree).
  String pathLabel(String locationId) {
    final names = <String>[];
    var current = _byId[locationId];
    if (current == null) return locationId;
    final warehouse = _warehouseById[current.warehouseId];
    var guard = 0; // a cycle can't happen (server-enforced) but never loop forever
    while (current != null && guard++ < 64) {
      names.insert(0, current.name);
      current = current.parentId == null ? null : _byId[current.parentId!];
    }
    if (warehouse != null) names.insert(0, warehouse.name);
    return names.join(' › ');
  }
}
