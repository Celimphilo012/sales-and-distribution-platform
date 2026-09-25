import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/workstream_manager.dart';
import 'workstream_managers_api.dart';

final workstreamManagersApiProvider = Provider<WorkstreamManagersApi>(
  (ref) => WorkstreamManagersApi(ref.watch(apiClientProvider)),
);

final workstreamManagersProvider = FutureProvider.autoDispose.family<List<WorkstreamManager>, String>((
  ref,
  workstreamId,
) {
  return ref.watch(workstreamManagersApiProvider).listForWorkstream(workstreamId);
});

/// The current user's own assignments — drives any "which workstreams can I
/// touch" UI (e.g. narrowing a category/workstream picker for a scoped
/// manager). Empty means unscoped.
final myWorkstreamAssignmentsProvider = FutureProvider.autoDispose<List<MyWorkstreamAssignment>>((ref) {
  return ref.watch(workstreamManagersApiProvider).listMine();
});
