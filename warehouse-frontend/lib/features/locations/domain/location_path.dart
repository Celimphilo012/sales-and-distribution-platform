import 'location.dart';

/// The real `GET /inventory/balances` response embeds only a flat
/// `{id, name, code, warehouseId}` for a balance's location — no ancestor
/// chain (confirmed against the real API in step 6d). This resolves the
/// full Warehouse → Zone → ... → Bin path client-side from an already-loaded
/// flat location list (e.g. `warehouseLocationsProvider`'s result — the same
/// per-warehouse fetch 6c uses), by walking `parentId` up from [locationId].
///
/// Returns root-first (`[warehouse-level root, ..., locationId itself]`). If
/// [locationId] isn't found in [all], returns an empty list; a cycle (should
/// never happen — the backend's `assertNoCycle` prevents it) is guarded
/// against so this can never loop forever.
List<Location> locationPath(List<Location> all, String locationId) {
  final byId = {for (final location in all) location.id: location};
  final path = <Location>[];
  final visited = <String>{};

  String? currentId = locationId;
  while (currentId != null) {
    final location = byId[currentId];
    if (location == null || !visited.add(currentId)) break;
    path.add(location);
    currentId = location.parentId;
  }

  return path.reversed.toList();
}

/// Renders a resolved [path] as a single breadcrumb string, e.g.
/// "Inventory Demo Warehouse › Level A". Includes each segment's own name
/// only (not its code) to keep the common case readable.
String locationPathLabel(List<Location> path, {String separator = ' › '}) {
  return path.map((location) => location.name).join(separator);
}
