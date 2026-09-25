import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/workstream.dart';
import 'workstreams_api.dart';

final workstreamsApiProvider = Provider<WorkstreamsApi>((ref) => WorkstreamsApi(ref.watch(apiClientProvider)));

/// An uploaded workstream image's raw bytes — mirrors `productImageFileProvider`.
final workstreamImageFileProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, workstreamId) {
  return ref.watch(workstreamsApiProvider).getImageFileBytes(workstreamId);
});

/// Keyed by `includeInactive` — the category tree / product-form picker
/// (active only) and the workstream-management screen (everything, so it
/// can reactivate) get independent caches, same pattern as
/// `categoriesProvider`/`warehousesProvider`.
final workstreamsProvider = FutureProvider.autoDispose.family<List<Workstream>, bool>((ref, includeInactive) {
  return ref.watch(workstreamsApiProvider).list(includeInactive: includeInactive);
});

void invalidateWorkstreams(WidgetRef ref) {
  ref.invalidate(workstreamsProvider(true));
  ref.invalidate(workstreamsProvider(false));
}
