import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/category.dart';
import '../domain/category_tree.dart';
import 'categories_api.dart';

final categoriesApiProvider = Provider<CategoriesApi>((ref) => CategoriesApi(ref.watch(apiClientProvider)));

/// Keyed by `includeInactive` so the catalogue (active only, for pickers)
/// and the category-management screen (everything, so it can reactivate)
/// each get their own cached fetch instead of one screen's filter leaking
/// into the other's.
final categoriesProvider = FutureProvider.autoDispose.family<List<Category>, bool>((ref, includeInactive) {
  return ref.watch(categoriesApiProvider).list(includeInactive: includeInactive);
});

final categoryTreeProvider = Provider.autoDispose.family<AsyncValue<List<CategoryNode>>, bool>((
  ref,
  includeInactive,
) {
  return ref.watch(categoriesProvider(includeInactive)).whenData(buildCategoryTree);
});

/// Both cached fetches (active-only and everything) are stale after any
/// category mutation — invalidate both rather than tracking which one a
/// given screen happened to be watching.
void invalidateCategories(WidgetRef ref) {
  ref.invalidate(categoriesProvider(true));
  ref.invalidate(categoriesProvider(false));
}
