import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/product_image.dart';
import '../domain/product_status.dart';
import 'products_list_providers.dart';
import 'widgets/network_image_or_placeholder.dart';

/// Read-only product detail: images, every field, category, status — plus
/// permission-gated edit / soft-delete actions.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));

    return productAsync.when(
      loading: () => const LoadingStateView(message: 'Loading product…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load this product.',
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
      ),
      data: (product) => _ProductDetailBody(product: product, canManage: canManage),
    );
  }
}

class _ProductDetailBody extends ConsumerWidget {
  const _ProductDetailBody({required this.product, required this.canManage});

  final Product product;
  final bool canManage;

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate product?',
      message:
          'This marks "${product.name}" inactive. It stays visible in historical orders and '
          'inventory records — it is not deleted.',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(productsApiProvider).deactivate(product.id);
      invalidateProduct(ref, product.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deactivated')));
      }
    } on AppError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(productsApiProvider).reactivate(product.id);
      invalidateProduct(ref, product.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product reactivated')));
      }
    } on AppError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to products',
              onPressed: () => context.go(RoutePaths.products),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(product.name, style: theme.textTheme.headlineSmall)),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(
              label: product.status.label,
              tone: product.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
            ),
          ],
        ),
        if (canManage) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go(RoutePaths.productEdit(product.id)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              if (product.status == ProductStatus.active)
                OutlinedButton.icon(
                  onPressed: () => _deactivate(context, ref),
                  icon: const Icon(Icons.block),
                  label: const Text('Deactivate'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _reactivate(context, ref),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Reactivate'),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (product.images.isNotEmpty) ...[
          _ProductImageGallery(images: product.images),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'SKU', value: product.sku),
              _DetailRow(label: 'Category', value: product.category?.name ?? '—'),
              _DetailRow(
                label: 'Description',
                value: (product.description?.isNotEmpty ?? false) ? product.description! : '—',
              ),
              _DetailRow(label: 'Selling price', value: product.sellingPrice.toStringAsFixed(2)),
              _DetailRow(label: 'Cost price', value: product.costPrice?.toStringAsFixed(2) ?? '—'),
              _DetailRow(label: 'Unit of measure', value: product.uom),
              _DetailRow(label: 'Min stock level', value: product.minStockLevel.toStringAsFixed(2)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ProductImageGallery extends StatelessWidget {
  const _ProductImageGallery({required this.images});

  final List<ProductImage> images;

  @override
  Widget build(BuildContext context) {
    final primary = images.firstWhere((i) => i.isPrimary, orElse: () => images.first);

    return AppCard(
      title: 'Images',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: AspectRatio(aspectRatio: 16 / 9, child: NetworkImageOrPlaceholder(url: primary.url)),
          ),
          if (images.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetworkImageOrPlaceholder(url: image.url),
                          if (image.isPrimary)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Icon(Icons.star, size: 16, color: Theme.of(context).colorScheme.primary),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
