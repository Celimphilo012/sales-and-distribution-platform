import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../products/domain/product.dart';
import 'product_search_field.dart';

/// Form-embeddable product picker: a compact "Product: X (Change)" summary
/// once picked, expanding back to the full [ProductSearchField] (reused as-is
/// from 6d — same catalogue search, not duplicated) when there's no
/// selection yet or the user asks to change it.
class ProductPickerField extends StatelessWidget {
  const ProductPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final Product? value;
  final ValueChanged<Product> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (value == null) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: errorText),
        child: ProductSearchField(onSelected: onChanged),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: errorText),
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
          TextButton(
            onPressed: () => _showPicker(context),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ProductSearchField(
              onSelected: (product) {
                Navigator.of(context, rootNavigator: true).pop();
                onChanged(product);
              },
            ),
          ),
        ),
      ),
    );
  }
}
