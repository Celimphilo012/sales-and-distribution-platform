import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../../inventory/data/inventory_providers.dart';
import '../../../inventory/domain/inventory_balance.dart';
import '../../../inventory/presentation/widgets/product_search_field.dart';
import '../../../locations/domain/location.dart';
import '../../../products/domain/product.dart';

/// The Transfer form's product field. It adapts to what's already known:
///
///  * a product is chosen  → a compact summary with "Change";
///  * no From location yet → the catalogue search (any product; the form then
///    works out where it is stocked);
///  * a From location is set → a searchable list of the items actually held
///    in THAT location, each with its available quantity — so you pick from
///    what can really be moved instead of hunting through the catalogue.
class TransferProductField extends StatelessWidget {
  const TransferProductField({
    super.key,
    required this.from,
    required this.value,
    required this.onChanged,
    required this.onClear,
    this.errorText,
  });

  final Location? from;
  final InventoryBalanceProductRef? value;
  final ValueChanged<InventoryBalanceProductRef> onChanged;
  final VoidCallback onClear;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (value != null) {
      return InputDecorator(
        decoration: InputDecoration(labelText: 'Product', errorText: errorText),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value!.name, style: theme.textTheme.bodyMedium),
                  Text(
                    '${value!.sku} · ${value!.uom}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(onPressed: onClear, child: const Text('Change')),
          ],
        ),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(labelText: 'Product', errorText: errorText),
      child: from == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductSearchField(onSelected: (product) => onChanged(productRefOf(product))),
                Text(
                  'Tip: choose a From location first to list everything stored there.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            )
          : LocationItemsList(location: from!, onSelected: onChanged),
    );
  }
}

/// A catalogue [Product] reduced to the four fields a transfer needs (the
/// same shape the balances API embeds), so both entry paths — catalogue
/// search and "items in this location" — yield one type.
InventoryBalanceProductRef productRefOf(Product product) =>
    InventoryBalanceProductRef(id: product.id, sku: product.sku, name: product.name, uom: product.uom);

/// Every item with stock in [location], filterable by name or SKU. Items
/// whose stock is all reserved are shown but can't be picked (nothing is
/// available to move).
class LocationItemsList extends ConsumerStatefulWidget {
  const LocationItemsList({super.key, required this.location, required this.onSelected});

  final Location location;
  final ValueChanged<InventoryBalanceProductRef> onSelected;

  @override
  ConsumerState<LocationItemsList> createState() => _LocationItemsListState();
}

class _LocationItemsListState extends ConsumerState<LocationItemsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = widget.location;
    final balancesAsync = ref.watch(locationBalancesProvider(location.id));

    return balancesAsync.when(
      loading: () => const LoadingStateView(message: 'Loading items…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the items in this location.',
        onRetry: () => ref.invalidate(locationBalancesProvider(location.id)),
      ),
      data: (balances) {
        final stocked = [
          for (final b in balances)
            if (b.onHand > 0) b,
        ]..sort((a, b) => a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()));

        if (stocked.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Nothing is stored in ${location.name} (${location.code}) — there is nothing to transfer from here.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }

        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty
            ? stocked
            : [
                for (final b in stocked)
                  if (b.product.name.toLowerCase().contains(q) || b.product.sku.toLowerCase().contains(q)) b,
              ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Search items in ${location.name}',
              hintText: 'SKU or name',
              prefixIcon: Icons.search,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              q.isEmpty
                  ? '${stocked.length} ${stocked.length == 1 ? 'item' : 'items'} in this location'
                  : '${shown.length} of ${stocked.length} items match',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (shown.isEmpty)
              const EmptyStateView(title: 'No matching items in this location', icon: Icons.search_off)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final b = shown[index];
                      final movable = b.available > 0;
                      return ListTile(
                        enabled: movable,
                        title: Text(b.product.name),
                        subtitle: Text(
                          movable
                              ? '${b.product.sku} · ${formatQuantity(b.available)} ${b.product.uom} available'
                                    '${b.reserved > 0 ? ' (${formatQuantity(b.reserved)} reserved)' : ''}'
                              : '${b.product.sku} · all ${formatQuantity(b.onHand)} ${b.product.uom} reserved',
                        ),
                        trailing: movable ? const Icon(Icons.chevron_right) : null,
                        onTap: movable ? () => widget.onSelected(b.product) : null,
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
