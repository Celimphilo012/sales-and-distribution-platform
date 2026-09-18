import 'package:flutter/material.dart';

/// Standard labeled text field with consistent validation-error display.
/// Wraps [TextFormField] so every form in the app renders errors the same
/// way instead of each screen styling its own.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
    this.prefixIcon,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool enabled;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      enabled: enabled,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      ),
    );
  }
}
