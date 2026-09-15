import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/products_filter.dart';

/// Filter/search state for the products list — a plain [Notifier] so it
/// survives navigating away to a product's detail screen and back (unlike
/// local widget state, which is torn down when the route unmounts).
class ProductsFilterNotifier extends Notifier<ProductsFilter> {
  @override
  ProductsFilter build() => const ProductsFilter();

  void setSearch(String? value) => state = state.copyWith(search: value);

  void setCategory(String? categoryId) => state = state.copyWith(categoryId: categoryId);

  void setStatusFilter(ProductStatusFilter filter) => state = state.copyWith(statusFilter: filter);
}

final productsFilterProvider = NotifierProvider<ProductsFilterNotifier, ProductsFilter>(
  ProductsFilterNotifier.new,
);

/// Re-fetches whenever [productsFilterProvider] changes. `GET /products`
/// has no pagination param, so this always holds the complete filtered list.
final productsListProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  final filter = ref.watch(productsFilterProvider);
  return ref.watch(productsApiProvider).list(filter);
});

final productDetailProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) {
  return ref.watch(productsApiProvider).getById(id);
});

/// Both the list and the one detail entry are stale after any mutation to
/// that product.
void invalidateProduct(WidgetRef ref, String id) {
  ref.invalidate(productsListProvider);
  ref.invalidate(productDetailProvider(id));
}
