import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/product_image.dart';
import '../domain/product_status.dart';
import 'products_list_providers.dart';
import 'widgets/category_display.dart';
import 'widgets/product_image_view.dart';

/// The product row/tile's own click target — a scrollable popup with the
/// full product detail (images, fields, attributes) and, right there,
/// permission-gated Edit / Deactivate actions. Replaces navigating to a
/// whole new route just to look at one product: the ROUTE (`/products/:id`,
/// `ProductDetailScreen`) still exists too (a saved product still lands
/// there, and Edit's own Cancel button still returns to it) — this dialog
/// is just the products LIST's own faster, lighter path to the same data.
Future<void> showProductDetailDialog(BuildContext context, String productId) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ProductDetailDialog(productId: productId),
  );
}

class _ProductDetailDialog extends ConsumerWidget {
  const _ProductDetailDialog({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));

    return AppDialog(
      title: productAsync.value?.name ?? 'Product',
      maxWidth: 640,
      content: productAsync.when(
        loading: () => const SizedBox(
          height: 160,
          child: LoadingStateView(message: 'Loading product…'),
        ),
        error: (error, stackTrace) => SizedBox(
          height: 160,
          child: ErrorStateView(
            message: error is AppError ? error.message : 'Could not load this product.',
            onRetry: () => ref.invalidate(productDetailProvider(productId)),
          ),
        ),
        data: (product) => _ProductDetailBody(product: product),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
        if (canManage && productAsync.value != null) ...[
          if (productAsync.value!.status == ProductStatus.active)
            OutlinedButton.icon(
              onPressed: () => _deactivate(context, ref, productAsync.value!),
              icon: const Icon(Icons.block),
              label: const Text('Deactivate'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _reactivate(context, ref, productAsync.value!),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Reactivate'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              context.go(RoutePaths.productEdit(productId));
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ],
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref, Product product) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate product?',
      message:
          'This marks "${product.name}" inactive. It stays visible in historical inventory '
          'records — it is not deleted.',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(productsApiProvider).deactivate(product.id);
      invalidateProduct(ref, product.id);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref, Product product) async {
    try {
      await ref.read(productsApiProvider).reactivate(product.id);
      invalidateProduct(ref, product.id);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ProductDetailBody extends StatelessWidget {
  const _ProductDetailBody({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.sku,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            StatusBadge(
              label: product.status.label,
              tone: product.status == ProductStatus.active ? StatusTone.success : StatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (product.images.isNotEmpty) ...[
          _ProductImageGallery(productId: product.id, images: product.images),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Category', valueWidget: CategoryDisplay(category: product.category)),
              _DetailRow(
                label: 'Description',
                value: (product.description?.isNotEmpty ?? false) ? product.description! : '—',
              ),
              _DetailRow(label: 'Selling price', value: product.sellingPrice.toStringAsFixed(2)),
              _DetailRow(label: 'Cost price', value: product.costPrice?.toStringAsFixed(2) ?? '—'),
              _DetailRow(label: 'Unit of measure', value: product.uom),
              _DetailRow(label: 'Min stock level', value: product.minStockLevel.toStringAsFixed(2)),
              _DetailRow(
                label: 'Stock on hand (all locations)',
                value: formatQuantity(product.totalOnHand),
                valueColor: product.isLowStock ? Theme.of(context).colorScheme.error : null,
              ),
            ],
          ),
        ),
        if (product.attributes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            title: 'Attributes',
            subtitle: 'Descriptive metadata — not variants',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final attribute in product.attributes)
                  _DetailRow(
                    label: attribute.attributeType.name,
                    value: (attribute.attributeType.unit?.isNotEmpty ?? false)
                        ? '${attribute.value} ${attribute.attributeType.unit}'
                        : attribute.value,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, this.value, this.valueColor, this.valueWidget}) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? valueWidget;

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
          Expanded(
            child: valueWidget ?? Text(value!, style: valueColor != null ? TextStyle(color: valueColor) : null),
          ),
        ],
      ),
    );
  }
}

class _ProductImageGallery extends StatelessWidget {
  const _ProductImageGallery({required this.productId, required this.images});

  final String productId;
  final List<ProductImage> images;

  @override
  Widget build(BuildContext context) {
    final primary = images.firstWhere((i) => i.isPrimary, orElse: () => images.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ProductImageView(image: primary, productId: productId),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final image = images[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProductImageView(image: image, productId: productId),
                        if (image.isPrimary)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Icon(Icons.star, size: 14, color: Theme.of(context).colorScheme.primary),
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
    );
  }
}
