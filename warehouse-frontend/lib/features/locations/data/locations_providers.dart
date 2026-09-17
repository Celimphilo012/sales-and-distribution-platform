import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/location.dart';
import '../domain/location_tree.dart';
import 'locations_api.dart';

final locationsApiProvider = Provider<LocationsApi>((ref) => LocationsApi(ref.watch(apiClientProvider)));

/// The full location forest for one warehouse: fetch its root locations,
/// then the real subtree of EACH root (there can be more than one), and
/// concatenate — `buildLocationTree` then regroups the combined flat list
/// by `parentId` into a proper forest. This is what actually exercises
/// `GET /locations/:id/subtree` rather than sidestepping it with a single
/// flat `GET /locations?warehouseId=` call.
final warehouseLocationsProvider = FutureProvider.autoDispose
    .family<List<Location>, ({String warehouseId, bool includeInactive})>((ref, args) async {
      final api = ref.watch(locationsApiProvider);
      final roots = await api.roots(args.warehouseId, includeInactive: args.includeInactive);

      final all = <Location>[];
      for (final root in roots) {
        all.addAll(await api.subtree(root.id, includeInactive: args.includeInactive));
      }
      return all;
    });

final warehouseLocationTreeProvider = Provider.autoDispose
    .family<AsyncValue<List<LocationNode>>, ({String warehouseId, bool includeInactive})>((ref, args) {
      return ref.watch(warehouseLocationsProvider(args)).whenData(buildLocationTree);
    });

void invalidateWarehouseLocations(WidgetRef ref, String warehouseId) {
  ref.invalidate(warehouseLocationsProvider((warehouseId: warehouseId, includeInactive: true)));
  ref.invalidate(warehouseLocationsProvider((warehouseId: warehouseId, includeInactive: false)));
}
