import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';

/// `GET /dashboard` — the F2 proof that an authenticated request flows
/// end to end through [ApiClient] (bearer token attached, 401s silently
/// refreshed). Returns the raw JSON map; a typed model + polished UI is a
/// later phase, per the F2 scope.
final dashboardSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/dashboard'));
  return response.data!;
});
