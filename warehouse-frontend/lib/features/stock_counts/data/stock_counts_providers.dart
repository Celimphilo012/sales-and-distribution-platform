import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/stock_count.dart';
import 'stock_counts_api.dart';

final stockCountsApiProvider = Provider<StockCountsApi>((ref) => StockCountsApi(ref.watch(apiClientProvider)));

/// The counts list/history, optionally filtered by status. `null` returns
/// every count regardless of status.
final stockCountsListProvider = FutureProvider.autoDispose.family<List<StockCount>, StockCountStatus?>((ref, status) {
  return ref.watch(stockCountsApiProvider).list(status: status);
});

final stockCountProvider = FutureProvider.autoDispose.family<StockCount, String>((ref, id) {
  return ref.watch(stockCountsApiProvider).getOne(id);
});
