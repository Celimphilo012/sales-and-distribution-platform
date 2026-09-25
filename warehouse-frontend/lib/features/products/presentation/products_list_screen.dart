import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category_tree.dart';
import '../domain/product.dart';
import '../domain/product_status.dart';
import '../domain/products_filter.dart';
import 'product_detail_dialog.dart';
import 'products_list_providers.dart';
import 'widgets/category_display.dart';
import 'widgets/product_image_view.dart';

/// The catalogue list: search + category/status filters, a stats strip, a
/// list/table/grid view switcher, and a permission-gated "New product"
/// action. PROTOTYPE for the app-wide list/table/grid + stats + compact
/// pattern — build it here first, roll the same shape out to every other
/// records screen once this one's approved.
class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() => _ProductsListScreenState();
}

class _ProductsListScreenState extends ConsumerState<ProductsListScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;
  ViewMode _view = ViewMode.table;

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
      // Compact: tighter page padding and inter-section spacing than the
      // rest of the app currently uses (AppSpacing.lg -> .md), scoped to
      // this one screen for now.
      padding: const EdgeInsets.all(AppSpacing.md),
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
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => context.go(RoutePaths.productNew),
                  icon: const Icon(Icons.add),
                  label: const Text('New product'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          productsAsync.maybeWhen(
            data: (products) => _ProductsStats(products: products),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap (for the filters reflowing on narrow widths) can't sit
              // directly next to a Spacer — Spacer is Expanded under the
              // hood, and Expanded only works inside Flex (Row/Column), not
              // Wrap. This outer Row does the "push right" instead; the
              // Wrap only ever owns the filter fields' own reflow.
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: AppTextField(
                        label: 'Search',
                        controller: _searchController,
                        hintText: 'SKU or name',
                        prefixIcon: Icons.search,
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    SizedBox(
                      width: 200,
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
                      width: 150,
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
              ),
              const SizedBox(width: AppSpacing.sm),
              ViewModeToggle(value: _view, onChanged: (mode) => setState(() => _view = mode)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: productsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading products…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load products.',
                onRetry: () => ref.invalidate(productsListProvider),
              ),
              data: (products) => switch (_view) {
                ViewMode.table => _ProductsTable(products: products),
                ViewMode.list => _ProductsCompactList(products: products),
                ViewMode.grid => _ProductsGrid(products: products),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsStats extends StatelessWidget {
  const _ProductsStats({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final active = products.where((p) => p.status == ProductStatus.active).length;
    final inactive = products.length - active;
    final lowStock = products.where((p) => p.isLowStock).length;
    final avgPrice = products.isEmpty
        ? null
        : products.map((p) => p.sellingPrice).reduce((a, b) => a + b) / products.length;
    final totalStock = products.fold<double>(0, (sum, p) => sum + p.totalOnHand);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'shown', value: '${products.length}', icon: Icons.inventory_2_outlined),
        StatTile(label: 'active', value: '$active', tone: StatusTone.success, icon: Icons.check_circle_outline),
        if (inactive > 0)
          StatTile(label: 'inactive', value: '$inactive', tone: StatusTone.neutral, icon: Icons.block_outlined),
        if (lowStock > 0)
          StatTile(label: 'low stock', value: '$lowStock', tone: StatusTone.warning, icon: Icons.warning_amber_outlined),
        StatTile(label: 'total stock', value: formatQuantity(totalStock), icon: Icons.inventory_outlined),
        StatTile(
          label: 'avg. price',
          value: avgPrice == null ? '—' : avgPrice.toStringAsFixed(2),
          icon: Icons.sell_outlined,
        ),
      ],
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<Product>(
      rows: products,
      emptyTitle: 'No products found',
      emptyMessage: 'Try adjusting your search or filters.',
      onRowTap: (product) => showProductDetailDialog(context, product.id),
      columns: [
        AppDataColumn(
          label: '',
          cellBuilder: (p) => _RowThumbnail(product: p),
        ),
        AppDataColumn(label: 'SKU', cellBuilder: (p) => Text(p.sku)),
        AppDataColumn(label: 'Name', cellBuilder: (p) => Text(p.name)),
        AppDataColumn(label: 'Category', cellBuilder: (p) => CategoryDisplay(category: p.category, compact: true)),
        AppDataColumn(label: 'UOM', cellBuilder: (p) => Text(p.uom)),
        AppDataColumn(
          label: 'Price',
          numeric: true,
          cellBuilder: (p) => Text(p.sellingPrice.toStringAsFixed(2)),
        ),
        AppDataColumn(
          label: 'Min stock',
          numeric: true,
          cellBuilder: (p) => Text(formatQuantity(p.minStockLevel)),
        ),
        AppDataColumn(
          label: 'Stock',
          numeric: true,
          cellBuilder: (p) => Text(
            formatQuantity(p.totalOnHand),
            style: p.isLowStock ? TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600) : null,
          ),
        ),
        AppDataColumn(
          label: 'Status',
          cellBuilder: (p) => StatusBadge(
            label: p.status.label,
            tone: p.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
          ),
        ),
      ],
    );
  }
}

/// A small square thumbnail for the table's leading (unlabeled) column —
/// falls back to a placeholder icon when the product has no image, same
/// fallback the grid view uses.
class _RowThumbnail extends StatelessWidget {
  const _RowThumbnail({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final image = product.primaryImage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: SizedBox(
        width: 32,
        height: 32,
        child: image == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : ProductImageView(image: image, productId: product.id),
      ),
    );
  }
}

/// Denser than [AppDataTable]'s own mobile card fallback — one thin row per
/// product (no card chrome), everything on one line, a hairline between
/// rows instead of card gaps. Meant for scanning a lot of rows quickly.
class _ProductsCompactList extends StatelessWidget {
  const _ProductsCompactList({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (products.isEmpty) {
      return const EmptyStateView(title: 'No products found', message: 'Try adjusting your search or filters.');
    }

    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final p = products[index];
        return InkWell(
          onTap: () => showProductDetailDialog(context, p.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(p.sku, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 3,
                  child: Text(p.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
                // Inline tag rather than the stacked layout Table/Detail use
                // — this view's whole point is one line per product, so the
                // sub-category still reads as a distinct tag, just beside
                // the parent name instead of below it.
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          p.category?.parent?.name ?? p.category?.name ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      if (p.category?.parent != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            p.category!.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    p.sellingPrice.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    formatQuantity(p.totalOnHand),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.isLowStock ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                      fontWeight: p.isLowStock ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: StatusBadge(
                      label: p.status.label,
                      tone: p.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A visual, browse-by-image mode — most useful once products regularly
/// carry an image; falls back to a plain placeholder tile otherwise.
class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (products.isEmpty) {
      return const EmptyStateView(title: 'No products found', message: 'Try adjusting your search or filters.');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < Breakpoints.dataTableMin;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: compact ? 160 : 200,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            // Enough headroom below the image for name/SKU, a price+stock
            // row, and a status-badge row without overflowing — a 1:1 image
            // at 0.78 left only ~56px for that block, which didn't fit; 0.62
            // fit the original 2-line block but not the extra stock row
            // added later, so this leaves more margin still.
            childAspectRatio: 0.54,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final p = products[index];
            final image = p.primaryImage;
            return InkWell(
              onTap: () => showProductDetailDialog(context, p.id),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSm)),
                        child: image == null
                            ? ColoredBox(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  size: 28,
                                ),
                              )
                            : ProductImageView(image: image, productId: p.id),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            p.sku,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(child: Text(p.sellingPrice.toStringAsFixed(2), style: theme.textTheme.bodySmall)),
                              Icon(
                                Icons.inventory_outlined,
                                size: 12,
                                color: p.isLowStock ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                formatQuantity(p.totalOnHand),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: p.isLowStock ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: p.isLowStock ? FontWeight.w600 : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          StatusBadge(
                            label: p.status.label,
                            tone: p.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
