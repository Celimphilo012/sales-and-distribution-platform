import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../inventory/domain/inventory_balance.dart';
import '../../../inventory/domain/product_location_stock.dart';
import '../../../locations/domain/location.dart';

/// Shown when the chosen product is stocked in MORE than one location, so
/// the form can't pick the From location on its own: lists each place with
/// its full path and available quantity; tapping one chooses it.
class TransferSourceChooser extends StatelessWidget {
  const TransferSourceChooser({super.key, required this.product, required this.sources, required this.onPick});

  final InventoryBalanceProductRef product;
  final List<ProductLocationStock> sources;
  final ValueChanged<Location> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...sources]..sort((a, b) => b.balance.available.compareTo(a.balance.available));

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${product.name} is stored in ${sources.length} locations',
            style: theme.textTheme.titleSmall,
          ),
          Text(
            'Choose where to transfer it from:',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final source in ordered)
            InkWell(
              onTap: source.path.isEmpty ? null : () => onPick(source.path.last),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(source.fullPathLabel, style: theme.textTheme.bodyMedium),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${formatQuantity(source.balance.available)} ${product.uom}',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
