import 'dart:typed_data';

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

/// Every product the viewer can see, active AND inactive — the console list
/// filters, searches and sorts client-side (as the prototype does), and the
/// pickers narrow it themselves. `GET /products` has no pagination.
final productsListProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(productsApiProvider).list(const ProductsFilter(includeInactive: true));
});

final productDetailProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) {
  return ref.watch(productsApiProvider).getById(id);
});

/// An uploaded product image's raw bytes — mirrors the stock-adjustments
/// feature's own `adjustmentPhotoProvider` (fetched lazily, only for images
/// that actually have an uploaded file rather than a pasted URL).
final productImageFileProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String productId, String imageId})>((ref, args) {
      return ref.watch(productsApiProvider).getImageFileBytes(args.productId, args.imageId);
    });

/// Both the list and the one detail entry are stale after any mutation to
/// that product.
void invalidateProduct(WidgetRef ref, String id) {
  ref.invalidate(productsListProvider);
  ref.invalidate(productDetailProvider(id));
}
