import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/warehouse_product.dart';
import 'product_search_field.dart';

/// Opens the catalogue search in a dialog and resolves with the picked
/// product, or `null` if dismissed. Used by the order form to add a line —
/// each call adds ONE product; the caller decides the quantity afterward.
Future<WarehouseProduct?> showProductPickerDialog(BuildContext context) {
  return showDialog<WarehouseProduct>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a product', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: ProductSearchField(
                    onSelected: (product) => Navigator.of(context, rootNavigator: true).pop(product),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
