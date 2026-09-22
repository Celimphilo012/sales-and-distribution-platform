import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/dashboard_summary.dart';
import 'dashboard_api.dart';

final dashboardApiProvider = Provider<DashboardApi>((ref) => DashboardApi(ref.watch(apiClientProvider)));

/// `autoDispose` (not kept alive across navigation) so leaving and returning
/// to the dashboard always shows current numbers, matching how the other
/// list screens' providers behave.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) {
  return ref.watch(dashboardApiProvider).get();
});
