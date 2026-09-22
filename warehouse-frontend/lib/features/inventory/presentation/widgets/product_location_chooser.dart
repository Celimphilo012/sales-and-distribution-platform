import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../domain/inventory_balance.dart';
import '../../domain/product_location_stock.dart';
import '../../../locations/domain/location.dart';

/// Shown when a product is stocked in MORE than one active leaf location, so
/// a form can't auto-detect a single "the" location on its own: lists each
/// place with its full path and on-hand quantity; tapping one resolves it.
///
/// Shared by every stock-movement screen that offers "pick a product, then
/// tell me where it currently lives" (Transfers' own `TransferSourceChooser`
/// predates this and keeps its transfer-specific wording; this is the
/// general-purpose version other screens — e.g. Stock Adjustments — use).
class ProductLocationChooser extends StatelessWidget {
  const ProductLocationChooser({
    super.key,
    required this.product,
    required this.sources,
    required this.onPick,
    this.promptLabel = 'Choose which one:',
  });

  final InventoryBalanceProductRef product;
  final List<ProductLocationStock> sources;
  final ValueChanged<Location> onPick;

  /// The line under "PRODUCT is stored in N locations" — callers phrase
  /// this for their own action ("Choose where to transfer it from:",
  /// "Choose which location to adjust:", ...).
  final String promptLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...sources]..sort((a, b) => b.balance.onHand.compareTo(a.balance.onHand));

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
          Text(promptLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                      '${formatQuantity(source.balance.onHand)} ${product.uom} on hand',
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
