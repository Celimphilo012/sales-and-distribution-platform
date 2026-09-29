/// Formats an amount in emalangeni (SZL) the way the app shows money
/// everywhere: `E 1,250.00`. Values come from the server (DECIMAL(12,2)),
/// so this only presents them — it never rounds business values.
String formatMoney(double value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final whole = fixed.substring(0, fixed.length - 3);
  final cents = fixed.substring(fixed.length - 2);
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${negative ? '-' : ''}E $grouped.$cents';
}
