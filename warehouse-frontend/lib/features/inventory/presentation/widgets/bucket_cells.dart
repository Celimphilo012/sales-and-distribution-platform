import 'package:flutter/material.dart';

import '../../../../shared/quantity_format.dart';
import '../../domain/inventory_balance.dart';

/// Shared cell widgets for the two inventory views' data tables, so
/// "reserved highlighted when non-zero" and "available shown prominently"
/// (rule 4: on_hand/reserved/damaged/lost/expired are distinct; available =
/// on_hand - reserved) render identically wherever a bucket split appears.

class ReservedQuantityCell extends StatelessWidget {
  const ReservedQuantityCell({super.key, required this.reserved});

  final double reserved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      formatQuantity(reserved),
      style: reserved > 0 ? TextStyle(color: theme.colorScheme.error) : null,
    );
  }
}

class AvailableQuantityCell extends StatelessWidget {
  const AvailableQuantityCell({super.key, required this.available});

  final double available;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      formatQuantity(available),
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
    );
  }
}

class ProductRefCell extends StatelessWidget {
  const ProductRefCell({super.key, required this.product});

  final InventoryBalanceProductRef product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(product.name, style: theme.textTheme.bodyMedium),
        Text(
          '${product.sku} · ${product.uom}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
