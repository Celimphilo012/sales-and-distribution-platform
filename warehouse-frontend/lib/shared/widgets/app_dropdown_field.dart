import 'package:flutter/material.dart';

/// Standard labeled dropdown, generic over the option type [T]. Pairs with
/// [AppTextField]/[AppNumberField] to give every form field in the app the
/// same label/helper/error presentation.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.validator,
    this.helperText,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      items: [for (final item in items) DropdownMenuItem(value: item, child: Text(itemLabel(item)))],
      onChanged: onChanged,
      validator: validator,
    );
  }
}
