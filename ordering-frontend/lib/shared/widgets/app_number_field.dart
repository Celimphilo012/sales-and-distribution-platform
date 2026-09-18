import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric text field — digits only (plus an optional decimal point),
/// sharing [AppTextField]'s label/helper/error presentation.
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    super.key,
    required this.label,
    this.controller,
    this.helperText,
    this.validator,
    this.allowDecimal = false,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? helperText;
  final String? Function(String?)? validator;
  final bool allowDecimal;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        allowDecimal
            ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(labelText: label, helperText: helperText),
    );
  }
}
