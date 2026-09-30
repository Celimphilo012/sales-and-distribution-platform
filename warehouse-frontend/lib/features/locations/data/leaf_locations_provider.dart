import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/nx/nx_form.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../domain/location.dart';
import '../domain/location_path.dart';
import 'locations_providers.dart';

/// A storage slot (an active LEAF location — the only place stock is held,
/// rule 5 / assertLeaf) with its warehouse and full path, ready for pickers.
class LeafLocation {
  const LeafLocation({required this.location, required this.warehouse, required this.path});

  final Location location;
  final Warehouse warehouse;

  /// Names from the warehouse's top-level area down to this slot.
  final List<String> path;

  String get id => location.id;
  String get code => location.code;
  String get pathLabel => path.join(' › ');

  /// "A-02-03 — Aisle A › Rack 02 › Level 03"
  String get label => '${location.code} — $pathLabel';

  /// A searchable picker option (matches code, path and warehouse).
  NxOption<String> option({String? trailing}) => NxOption(
    location.id,
    '${location.code} — ${path.isEmpty ? location.name : pathLabel}',
    sub: warehouse.name,
    search: '${warehouse.code} ${location.name}',
    trailing: trailing,
  );
}

/// Every active storage slot in every active warehouse the viewer can see,
/// sorted by warehouse then code — the destination / source / count pickers.
final leafLocationsProvider = FutureProvider.autoDispose<List<LeafLocation>>((ref) async {
  final warehouses = (await ref.watch(warehousesProvider(false).future)).where((w) => w.isActive).toList();
  final out = <LeafLocation>[];
  for (final w in warehouses) {
    final all = await ref.watch(warehouseLocationsProvider((warehouseId: w.id, includeInactive: false)).future);
    final parents = {for (final l in all) ?l.parentId};
    for (final l in all.where((l) => l.isActive && !parents.contains(l.id))) {
      out.add(LeafLocation(location: l, warehouse: w, path: locationPath(all, l.id).map((p) => p.name).toList()));
    }
  }
  out.sort((a, b) {
    final w = a.warehouse.name.compareTo(b.warehouse.name);
    return w != 0 ? w : a.location.code.compareTo(b.location.code);
  });
  return out;
});
