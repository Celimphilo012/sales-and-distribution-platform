import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/location.dart';
import 'leaf_location_picker.dart';

/// Form-embeddable version of [showLeafLocationPicker]: shows the current
/// pick (or a placeholder) with a button to open the picker dialog, wrapped
/// in an [InputDecorator] so it reads as a normal form field (label, error
/// text) alongside [AppTextField]/[AppNumberField]/[AppDropdownField].
class LeafLocationField extends StatelessWidget {
  const LeafLocationField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.excludeLocationId,
    this.errorText,
  });

  final String label;
  final Location? value;
  final ValueChanged<Location> onChanged;
  final String? excludeLocationId;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: errorText),
      child: Row(
        children: [
          Expanded(
            child: value == null
                ? Text(
                    'Not selected',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                : Text('${value!.name} (${value!.code})', style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              final picked = await showLeafLocationPicker(
                context,
                title: label,
                excludeLocationId: excludeLocationId,
                initialWarehouseId: value?.warehouseId,
              );
              if (picked != null) onChanged(picked);
            },
            child: Text(value == null ? 'Choose' : 'Change'),
          ),
        ],
      ),
    );
  }
}
