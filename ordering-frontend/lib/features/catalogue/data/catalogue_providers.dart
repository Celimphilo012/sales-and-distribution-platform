import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/warehouse_product.dart';
import 'catalogue_api.dart';

final catalogueApiProvider = Provider<CatalogueApi>((ref) => CatalogueApi(ref.watch(apiClientProvider)));

/// Product search for the order-line picker. A blank query still returns
/// results (unlike Warehouse's own product search) — `search` is optional
/// server-side, so an empty query just lists the (typically small) active
/// catalogue, letting a consultant browse rather than requiring a query
/// first.
final catalogueSearchResultsProvider = FutureProvider.autoDispose.family<List<WarehouseProduct>, String>((
  ref,
  query,
) {
  return ref.watch(catalogueApiProvider).search(query.trim().isEmpty ? null : query.trim());
});
