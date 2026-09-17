/// `is_active` is a MySQL/MariaDB TINYINT(1) — Prisma's own typed queries
/// (used by every warehouse/location endpoint except the locations subtree
/// read) already coerce it to a real JSON boolean before it reaches this
/// app, and the subtree endpoint's raw-query rows are coerced server-side
/// too (see the warehouse backend's `LocationsService.mapRow`). This
/// defends against the wire format ever regressing to a raw 0/1 without
/// assuming it currently does.
bool boolFromJson(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return false;
}

/// Prisma `Decimal` columns (prices, stock quantities) serialize as JSON
/// STRINGS on read (e.g. `"60.000"`), never numbers — confirmed against the
/// real API (ARCHITECTURE.md §E). Parses either representation defensively;
/// a missing/null value defaults to 0 rather than throwing, since every
/// caller here reads a required numeric column.
double numFromJson(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
