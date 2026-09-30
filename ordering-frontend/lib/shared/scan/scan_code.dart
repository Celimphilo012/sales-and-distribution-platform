/// What a scanned QR / barcode points at.
enum ScanKind { product, location, unknown }

/// A scanned code, parsed.
///
/// Labels printed by the console encode a record's PERMANENT id, never its
/// SKU or code, so a label keeps working after the SKU is renamed:
///   - products:  `WH:P:<id>`
///   - locations: `WH:L:<id>`
/// Anything else (a bare id, a SKU typed on a handheld scanner, a supplier's
/// barcode that happens to be the SKU) is [ScanKind.unknown] — the caller
/// matches [value] against ids and SKUs / location codes itself.
class ScanCode {
  const ScanCode(this.kind, this.value);

  final ScanKind kind;

  /// The id for product / location codes; the trimmed raw text otherwise.
  final String value;

  static const productPrefix = 'WH:P:';
  static const locationPrefix = 'WH:L:';

  static String forProduct(String id) => '$productPrefix$id';
  static String forLocation(String id) => '$locationPrefix$id';

  factory ScanCode.parse(String raw) {
    final s = raw.trim();
    final upper = s.toUpperCase();
    if (upper.startsWith(productPrefix)) return ScanCode(ScanKind.product, s.substring(productPrefix.length).trim());
    if (upper.startsWith(locationPrefix)) return ScanCode(ScanKind.location, s.substring(locationPrefix.length).trim());
    return ScanCode(ScanKind.unknown, s);
  }

  bool get isEmpty => value.isEmpty;

  /// Finds the [want] item this code points at: by id first, then (for a
  /// code that is not one of our labels) by its human code — SKU / location
  /// code — compared case-insensitively.
  T? match<T>(ScanKind want, Iterable<T> items, {required String Function(T) id, required String Function(T) code}) {
    if (isEmpty || (kind != ScanKind.unknown && kind != want)) return null;
    for (final x in items) {
      if (id(x) == value) return x;
    }
    if (kind != ScanKind.unknown) return null;
    final v = value.toLowerCase();
    for (final x in items) {
      if (code(x).toLowerCase() == v) return x;
    }
    return null;
  }
}
