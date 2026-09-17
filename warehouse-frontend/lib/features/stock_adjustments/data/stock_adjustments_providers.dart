import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/stock_adjustment.dart';
import 'stock_adjustments_api.dart';

final stockAdjustmentsApiProvider = Provider<StockAdjustmentsApi>(
  (ref) => StockAdjustmentsApi(ref.watch(apiClientProvider)),
);

/// The adjustments list, optionally filtered by status. `null` returns every
/// adjustment regardless of status — used by the stock-count detail screen to
/// find the adjustments a specific count created (matched client-side by
/// `reference == count.id`, since the real `ListAdjustmentsQueryDto` has no
/// `reference` filter).
final stockAdjustmentsListProvider = FutureProvider.autoDispose.family<List<StockAdjustment>, AdjustmentStatus?>((
  ref,
  status,
) {
  return ref.watch(stockAdjustmentsApiProvider).list(status: status);
});
