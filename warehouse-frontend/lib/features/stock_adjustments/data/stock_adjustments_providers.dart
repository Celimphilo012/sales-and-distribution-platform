import 'dart:typed_data';

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

/// An attached photo's bytes, fetched on demand and cached per adjustment —
/// [AdjustmentSummaryTile] only calls this for adjustments that actually
/// have one, so the queue never fetches image bytes for every row up front.
final adjustmentPhotoProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, adjustmentId) {
  return ref.watch(stockAdjustmentsApiProvider).getPhotoBytes(adjustmentId);
});
