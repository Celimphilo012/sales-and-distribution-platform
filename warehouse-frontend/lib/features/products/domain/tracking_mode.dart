/// Mirrors the backend's `TrackingMode` enum (`BULK` / `SERIAL`). Opt-in per
/// product — BULK is the default, unchanged quantity-ledger behaviour; SERIAL
/// gives each physical unit its own scannable code (`inventory_units`), so a
/// received/counted quantity is always derived from distinct scans, never typed.
enum TrackingMode {
  bulk,
  serial;

  static TrackingMode fromJson(String value) => switch (value) {
    'BULK' => TrackingMode.bulk,
    'SERIAL' => TrackingMode.serial,
    _ => throw ArgumentError('Unknown tracking mode: $value'),
  };

  String toJson() => switch (this) {
    TrackingMode.bulk => 'BULK',
    TrackingMode.serial => 'SERIAL',
  };

  String get label => switch (this) {
    TrackingMode.bulk => 'Bulk (quantity)',
    TrackingMode.serial => 'Serial (one code per unit)',
  };
}
