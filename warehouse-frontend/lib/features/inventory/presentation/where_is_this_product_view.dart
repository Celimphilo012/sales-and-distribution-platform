import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/inventory_providers.dart';
import '../domain/product_location_stock.dart';
import 'widgets/bucket_cells.dart';
import 'widgets/product_search_field.dart';

/// "Where is this product?" — the flagship 6d view: pick a product, see its
/// TOTAL on_hand across every location, then a per-location breakdown with
/// each location's full path and bucket split. Read-only.
///
/// [initialProductId] (from 6e-1's post-receive/-transfer confirmation link,
/// `?productId=`) auto-loads that product's breakdown instead of starting on
/// the search box — the concrete "write→read loop" proof.
class WhereIsThisProductView extends ConsumerStatefulWidget {
  const WhereIsThisProductView({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<WhereIsThisProductView> createState() => _WhereIsThisProductViewState();
}

class _WhereIsThisProductViewState extends ConsumerState<WhereIsThisProductView> {
  Product? _selected;
  bool _consumedInitial = false;

  void _changeProduct() {
    setState(() {
      _selected = null;
      _consumedInitial = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selected == null && widget.initialProductId != null && !_consumedInitial) {
      final productAsync = ref.watch(productDetailProvider(widget.initialProductId!));
      return productAsync.when(
        loading: () => const LoadingStateView(message: 'Loading product…'),
        error: (error, stackTrace) => ErrorStateView(
          message: error is AppError ? error.message : 'Could not load this product.',
          onRetry: () => ref.invalidate(productDetailProvider(widget.initialProductId!)),
        ),
        data: (product) {
          // Persist into local state after this frame (not during build) so
          // later builds take the normal "_selected != null" path and
          // "Change product" behaves exactly like a manual pick.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selected = product);
          });
          return _ProductBreakdown(product: product, onChangeProduct: _changeProduct);
        },
      );
    }

    if (_selected == null) {
      return ProductSearchField(onSelected: (product) => setState(() => _selected = product));
    }
    return _ProductBreakdown(product: _selected!, onChangeProduct: _changeProduct);
  }
}

class _ProductBreakdown extends ConsumerWidget {
  const _ProductBreakdown({required this.product, required this.onChangeProduct});

  final Product product;
  final VoidCallback onChangeProduct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final breakdownAsync = ref.watch(productStockBreakdownProvider(product.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleLarge),
                  Text(
                    '${product.sku} · ${product.uom}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onChangeProduct,
              icon: const Icon(Icons.search),
              label: const Text('Change product'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        breakdownAsync.when(
          loading: () => const LoadingStateView(message: 'Loading stock…'),
          error: (error, stackTrace) => ErrorStateView(
            message: error is AppError ? error.message : 'Could not load stock for this product.',
            onRetry: () => ref.invalidate(productStockBreakdownProvider(product.id)),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const EmptyStateView(
                title: 'No stock anywhere',
                message: 'This product currently has no inventory in any location.',
                icon: Icons.inventory_2_outlined,
              );
            }
            return Expanded(child: _BreakdownBody(rows: rows, uom: product.uom));
          },
        ),
      ],
    );
  }
}

class _BreakdownBody extends StatelessWidget {
  const _BreakdownBody({required this.rows, required this.uom});

  final List<ProductLocationStock> rows;
  final String uom;

  @override
  Widget build(BuildContext context) {
    final totalOnHand = rows.fold<double>(0, (sum, row) => sum + row.balance.onHand);
    final totalReserved = rows.fold<double>(0, (sum, row) => sum + row.balance.reserved);
    final totalAvailable = rows.fold<double>(0, (sum, row) => sum + row.balance.available);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TotalsSummary(
            totalOnHand: totalOnHand,
            totalReserved: totalReserved,
            totalAvailable: totalAvailable,
            uom: uom,
            locationCount: rows.length,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('By location', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          AppDataTable<ProductLocationStock>(rows: rows, columns: _buildColumns(rows)),
        ],
      ),
    );
  }

  List<AppDataColumn<ProductLocationStock>> _buildColumns(List<ProductLocationStock> rows) {
    final showDamaged = rows.any((r) => r.balance.damaged != 0);
    final showLost = rows.any((r) => r.balance.lost != 0);
    final showExpired = rows.any((r) => r.balance.expired != 0);

    return [
      AppDataColumn(label: 'Location', cellBuilder: (r) => Text(r.fullPathLabel)),
      AppDataColumn(
        label: 'On hand',
        numeric: true,
        cellBuilder: (r) => Text(formatQuantity(r.balance.onHand)),
      ),
      AppDataColumn(
        label: 'Reserved',
        numeric: true,
        cellBuilder: (r) => ReservedQuantityCell(reserved: r.balance.reserved),
      ),
      AppDataColumn(
        label: 'Available',
        numeric: true,
        cellBuilder: (r) => AvailableQuantityCell(available: r.balance.available),
      ),
      if (showDamaged)
        AppDataColumn(
          label: 'Damaged',
          numeric: true,
          cellBuilder: (r) => Text(formatQuantity(r.balance.damaged)),
        ),
      if (showLost)
        AppDataColumn(label: 'Lost', numeric: true, cellBuilder: (r) => Text(formatQuantity(r.balance.lost))),
      if (showExpired)
        AppDataColumn(
          label: 'Expired',
          numeric: true,
          cellBuilder: (r) => Text(formatQuantity(r.balance.expired)),
        ),
    ];
  }
}

class _TotalsSummary extends StatelessWidget {
  const _TotalsSummary({
    required this.totalOnHand,
    required this.totalReserved,
    required this.totalAvailable,
    required this.uom,
    required this.locationCount,
  });

  final double totalOnHand;
  final double totalReserved;
  final double totalAvailable;
  final String uom;
  final int locationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL ON HAND',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${formatQuantity(totalOnHand)} $uom',
                  style: theme.textTheme.headlineMedium,
                ),
                Text(
                  'across $locationCount location${locationCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _StatColumn(label: 'Reserved', value: totalReserved, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.xl),
          _StatColumn(label: 'Available', value: totalAvailable, color: theme.colorScheme.primary, emphasize: true),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.color, this.emphasize = false});

  final String label;
  final double value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          formatQuantity(value),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
