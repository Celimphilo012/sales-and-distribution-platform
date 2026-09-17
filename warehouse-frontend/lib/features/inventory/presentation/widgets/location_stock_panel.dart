import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_data_table.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../data/inventory_providers.dart';
import '../../domain/inventory_balance.dart';
import 'bucket_cells.dart';

/// "What's in this location?" — every product currently balanced at
/// [locationId], with its bucket split. Read-only (6d displays inventory;
/// it never moves stock). Self-contained so it can be embedded both by the
/// standalone "what's in this location" view AND by 6c's Warehouse
/// Structure detail panel (replacing its "coming in step 6d" placeholder).
class LocationStockPanel extends ConsumerWidget {
  const LocationStockPanel({super.key, required this.locationId});

  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(locationBalancesProvider(locationId));

    return balancesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingStateView(message: 'Loading stock…'),
      ),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load stock for this location.',
        onRetry: () => ref.invalidate(locationBalancesProvider(locationId)),
      ),
      data: (balances) {
        if (balances.isEmpty) {
          return const EmptyStateView(
            title: 'No stock here',
            message: 'This location currently holds no inventory.',
            icon: Icons.inventory_2_outlined,
          );
        }
        return AppDataTable<InventoryBalance>(rows: balances, columns: buildBucketColumns(balances));
      },
    );
  }
}

/// Column set for a location-centric balance list: Product/SKU, on_hand,
/// reserved, available (prominent), and damaged/lost/expired — but only
/// when at least one row in THIS list actually has a non-zero value in that
/// bucket, so the table doesn't carry permanently-empty columns.
List<AppDataColumn<InventoryBalance>> buildBucketColumns(List<InventoryBalance> balances) {
  final showDamaged = balances.any((b) => b.damaged != 0);
  final showLost = balances.any((b) => b.lost != 0);
  final showExpired = balances.any((b) => b.expired != 0);

  return [
    AppDataColumn(label: 'Product', cellBuilder: (b) => ProductRefCell(product: b.product)),
    AppDataColumn(label: 'On hand', numeric: true, cellBuilder: (b) => Text(formatQuantity(b.onHand))),
    AppDataColumn(
      label: 'Reserved',
      numeric: true,
      cellBuilder: (b) => ReservedQuantityCell(reserved: b.reserved),
    ),
    AppDataColumn(
      label: 'Available',
      numeric: true,
      cellBuilder: (b) => AvailableQuantityCell(available: b.available),
    ),
    if (showDamaged)
      AppDataColumn(label: 'Damaged', numeric: true, cellBuilder: (b) => Text(formatQuantity(b.damaged))),
    if (showLost) AppDataColumn(label: 'Lost', numeric: true, cellBuilder: (b) => Text(formatQuantity(b.lost))),
    if (showExpired)
      AppDataColumn(label: 'Expired', numeric: true, cellBuilder: (b) => Text(formatQuantity(b.expired))),
  ];
}
