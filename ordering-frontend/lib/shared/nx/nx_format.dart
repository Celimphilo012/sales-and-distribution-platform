/// Number and date formatting in the Warehouse Console's style (en-US
/// grouping, "29 Sep 2026", "10:42", "Yesterday") — no intl dependency.
library;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _group(String digits) => digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// `1,234` — whole numbers; up to 3 decimals kept for fractional quantities.
String fmtNum(num? value) {
  if (value == null) return '—';
  final negative = value < 0;
  final v = value.abs();
  final whole = v.truncate();
  var frac = '';
  if (v != whole) {
    frac = v.toStringAsFixed(3).split('.')[1].replaceFirst(RegExp(r'0+$'), '');
    if (frac.isNotEmpty) frac = '.$frac';
  }
  return '${negative ? '−' : ''}${_group('$whole')}$frac';
}

/// `53,456.10` — money, always two decimals.
String fmtMoney(num? value) {
  if (value == null) return '—';
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  // Ordering money is emalangeni (SZL): `E 1,250.00`.
  return '${negative ? '−' : ''}E ${_group(parts[0])}.${parts[1]}';
}

/// `+24` / `−6` / `0` — a signed change.
String fmtSigned(num value) => value == 0 ? '0' : '${value > 0 ? '+' : '−'}${fmtNum(value.abs())}';

/// `29 Sep 2026`.
String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// `10:42`.
String fmtTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// `29 Sep 2026 10:42`.
String fmtDateTime(DateTime? d) => d == null ? '—' : '${fmtDate(d)} ${fmtTime(d)}';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// `10:42` today, `Yesterday`, otherwise `27 Sep`.
String fmtWhen(DateTime? d, {DateTime? now}) {
  if (d == null) return '—';
  final l = d.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (_sameDay(l, today)) return fmtTime(l);
  if (_sameDay(l, today.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${l.day} ${_months[l.month - 1]}${l.year == today.year ? '' : ' ${l.year}'}';
}

/// Whole days since [d] (0 = today).
int daysSince(DateTime d, {DateTime? now}) {
  final a = d.toLocal();
  final b = (now ?? DateTime.now()).toLocal();
  return DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;
}

/// `today` / `4d waiting`.
String fmtWaiting(int days) => days <= 0 ? 'today' : '${days}d waiting';

/// `RELEASE_RESERVATION` → `release reservation`.
String humanEnum(String value) => value.replaceAll('_', ' ').toLowerCase();

/// `ON_HAND` → `On hand`.
String sentenceEnum(String value) {
  final h = humanEnum(value);
  return h.isEmpty ? h : '${h[0].toUpperCase()}${h.substring(1)}';
}

/// A number for an input box: no grouping, no trailing ".0".
String fmtPlain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
