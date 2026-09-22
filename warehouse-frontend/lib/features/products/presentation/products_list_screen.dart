import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category_tree.dart';
import '../domain/product.dart';
import '../domain/product_status.dart';
import '../domain/products_filter.dart';
import 'products_list_providers.dart';

/// The catalogue list: search + category/status filters, a responsive
/// [AppDataTable], and a permission-gated "New product" action. This is the
/// template every later feature's list screen copies.
class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Filter state (a non-autoDispose Notifier) survives navigating to a
    // product and back — seed the field from it so the search text doesn't
    // visually reset even though this State object is fresh.
    _searchController = TextEditingController(text: ref.read(productsFilterProvider).search ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(productsFilterProvider.notifier).setSearch(value.isEmpty ? null : value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final filter = ref.watch(productsFilterProvider);
    final productsAsync = ref.watch(productsListProvider);
    final categoriesAsync = ref.watch(categoryTreeProvider(false));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Products', style: theme.textTheme.headlineSmall)),
              if (canManage) ...[
                OutlinedButton.icon(
                  onPressed: () => context.go(RoutePaths.productImport),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import products'),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => context.go(RoutePaths.productNew),
                  icon: const Icon(Icons.add),
                  label: const Text('New product'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 280,
                child: AppTextField(
                  label: 'Search',
                  controller: _searchController,
                  hintText: 'SKU or name',
                  prefixIcon: Icons.search,
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(
                width: 220,
                child: categoriesAsync.when(
                  loading: () => const SizedBox(height: 56),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (tree) {
                    final flat = flattenCategoryTree(tree);
                    return AppDropdownField<String?>(
                      label: 'Category',
                      value: filter.categoryId,
                      items: [null, for (final node in flat) node.category.id],
                      itemLabel: (id) {
                        if (id == null) return 'All categories';
                        final node = flat.firstWhere((n) => n.category.id == id);
                        return '${'    ' * node.depth}${node.category.name}';
                      },
                      onChanged: (value) => ref.read(productsFilterProvider.notifier).setCategory(value),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: AppDropdownField<ProductStatusFilter>(
                  label: 'Status',
                  value: filter.statusFilter,
                  items: ProductStatusFilter.values,
                  itemLabel: (f) => f.label,
                  onChanged: (value) {
                    if (value != null) ref.read(productsFilterProvider.notifier).setStatusFilter(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: productsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading products…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load products.',
                onRetry: () => ref.invalidate(productsListProvider),
              ),
              data: (products) => AppDataTable<Product>(
                rows: products,
                emptyTitle: 'No products found',
                emptyMessage: 'Try adjusting your search or filters.',
                onRowTap: (product) => context.go(RoutePaths.productDetail(product.id)),
                columns: [
                  AppDataColumn(label: 'SKU', cellBuilder: (p) => Text(p.sku)),
                  AppDataColumn(label: 'Name', cellBuilder: (p) => Text(p.name)),
                  AppDataColumn(label: 'Category', cellBuilder: (p) => Text(p.category?.name ?? '—')),
                  AppDataColumn(
                    label: 'Price',
                    numeric: true,
                    cellBuilder: (p) => Text(p.sellingPrice.toStringAsFixed(2)),
                  ),
                  AppDataColumn(
                    label: 'Status',
                    cellBuilder: (p) => StatusBadge(
                      label: p.status.label,
                      tone: p.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
