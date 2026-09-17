/// Formats a [DateTime] as `YYYY-MM-DD HH:MM` (local time, zero-padded) —
/// the compact timestamp used wherever a record's "when" needs to show
/// without pulling in the `intl` package for one format.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final mo = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}
