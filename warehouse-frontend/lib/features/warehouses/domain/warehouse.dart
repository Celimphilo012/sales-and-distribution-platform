import '../../../shared/json_utils.dart';

/// Mirrors the backend's `Warehouse` model (`GET/POST/PATCH/DELETE
/// /warehouses`) — `{id, name, code, isActive}`, plus the list read's
/// [summary] (structure + stock totals).
class Warehouse {
  const Warehouse({required this.id, required this.name, required this.code, required this.isActive, this.summary});

  final String id;
  final String name;
  final String code;
  final bool isActive;

  /// Present on list reads only.
  final WarehouseSummary? summary;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    isActive: boolFromJson(json['isActive']),
    summary: json['summary'] is Map<String, dynamic> ? WarehouseSummary.fromJson(json['summary'] as Map<String, dynamic>) : null,
  );
}

/// Active locations, storage slots (leaves), summed slot capacity, units on
/// hand and active workstreams — DB aggregates from `GET /warehouses`.
class WarehouseSummary {
  const WarehouseSummary({this.locations = 0, this.slots = 0, this.capacity = 0, this.units = 0, this.workstreams = 0});

  final int locations;
  final int slots;
  final double capacity;
  final double units;
  final int workstreams;

  /// Units stored as a share of slot capacity (0 when no slot has a capacity).
  double get utilisation => capacity <= 0 ? 0 : units / capacity;

  factory WarehouseSummary.fromJson(Map<String, dynamic> json) => WarehouseSummary(
    locations: (json['locations'] as num?)?.toInt() ?? 0,
    slots: (json['slots'] as num?)?.toInt() ?? 0,
    capacity: (json['capacity'] as num?)?.toDouble() ?? 0,
    units: (json['units'] as num?)?.toDouble() ?? 0,
    workstreams: (json['workstreams'] as num?)?.toInt() ?? 0,
  );
}
