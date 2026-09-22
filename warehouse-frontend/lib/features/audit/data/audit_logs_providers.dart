import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/audit_log.dart';
import '../domain/audit_log_query.dart';
import 'audit_logs_api.dart';

final auditLogsApiProvider = Provider<AuditLogsApi>((ref) => AuditLogsApi(ref.watch(apiClientProvider)));

/// The filter+page state the Audit Log screen reads/writes. A plain
/// (non-autoDispose) `Notifier` so paging/filter state survives navigating
/// away and back within the same session — same pattern as `ProductsFilter`.
class AuditLogQueryNotifier extends Notifier<AuditLogQuery> {
  @override
  AuditLogQuery build() => const AuditLogQuery();

  void update(AuditLogQuery Function(AuditLogQuery) updater) {
    state = updater(state);
  }
}

final auditLogQueryProvider = NotifierProvider<AuditLogQueryNotifier, AuditLogQuery>(AuditLogQueryNotifier.new);

final auditLogsPageProvider = FutureProvider.autoDispose<AuditLogPage>((ref) {
  final query = ref.watch(auditLogQueryProvider);
  return ref.watch(auditLogsApiProvider).list(query);
});
