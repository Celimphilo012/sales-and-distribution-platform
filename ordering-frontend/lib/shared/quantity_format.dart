/// Formats an inventory-style quantity (backed by the DB's `Decimal(14,3)`
/// columns): a whole number shows with no decimal point (`60`, not `60.0`),
/// a fractional one keeps up to 3 places with trailing zeros trimmed
/// (`12.5`, not `12.500`).
String formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var formatted = value.toStringAsFixed(3);
  formatted = formatted.replaceFirst(RegExp(r'0+$'), '');
  formatted = formatted.replaceFirst(RegExp(r'\.$'), '');
  return formatted;
}
