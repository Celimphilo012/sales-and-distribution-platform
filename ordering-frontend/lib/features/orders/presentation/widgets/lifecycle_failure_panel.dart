import 'package:flutter/material.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../warehouse_locations/domain/warehouse_locations.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';

/// Shows why a lifecycle call didn't go through, in a way that matches what
/// actually happened:
///
///  * short stock → WHICH lines were short, and by how much (a manager needs
///    that to decide), with the reassurance that nothing changed;
///  * warehouse unreachable → a calm "safe to retry" note with a Retry button;
///  * anything else → the backend's message, verbatim.
class LifecycleFailurePanel extends StatelessWidget {
  const LifecycleFailurePanel({super.key, required this.failure, required this.order, this.locations, this.onRetry});

  final LifecycleFailure failure;
  final Order order;

  /// Used to name the location of a short line; without it the raw id shows.
  final WarehouseLocations? locations;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    switch (failure) {
      case InsufficientStockFailure(:final shortLines):
        return _Box(
          background: semantic.warningContainer,
          foreground: semantic.onWarningContainer,
          icon: Icons.inventory_2_outlined,
          title: 'Not enough stock — nothing was reserved',
          subtitle:
              'The order stays ${order.status.label}. Choose another location or reduce the quantity, then try again.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in shortLines)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_productName(line.productId), style: theme.textTheme.titleSmall),
                      Text(
                        locations?.pathLabel(line.locationId) ?? line.locationId,
                        style: theme.textTheme.bodySmall?.copyWith(color: semantic.onWarningContainer),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        children: [
                          Text('Requested: ${formatQuantity(line.requested)}'),
                          Text('Available: ${formatQuantity(line.available)}'),
                          Text(
                            'Short by: ${formatQuantity(line.shortBy)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case WarehouseUnavailableFailure():
        return _Box(
          background: semantic.warningContainer,
          foreground: semantic.onWarningContainer,
          icon: Icons.cloud_off_outlined,
          title: 'Warehouse temporarily unavailable',
          subtitle: "Nothing was changed on either side, so it's safe to try again.",
          child: onRetry == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
        );
      case OtherFailure(:final message):
        return _Box(
          background: theme.colorScheme.errorContainer,
          foreground: theme.colorScheme.onErrorContainer,
          icon: Icons.error_outline,
          title: message,
        );
      // The base type is sealed with exactly these three subclasses; the
      // failure-typed insufficient-stock case with no parsable lines never
      // reaches here (classifyLifecycleError returns OtherFailure for it).
    }
  }

  String _productName(String productId) {
    for (final item in order.items) {
      if (item.productId == productId) return item.productName ?? productId;
    }
    return productId;
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.title,
    this.subtitle,
    this.child,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(color: foreground)),
                  if (subtitle != null) Text(subtitle!),
                  ?child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
