import '../../../shared/json_utils.dart';

/// Mirrors the backend's `Warehouse` model (`GET/POST/PATCH/DELETE
/// /warehouses`) — `{id, name, code, isActive}` only, no timestamps
/// (confirmed against the real Prisma model; §G doesn't claim any).
class Warehouse {
  const Warehouse({required this.id, required this.name, required this.code, required this.isActive});

  final String id;
  final String name;
  final String code;
  final bool isActive;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    isActive: boolFromJson(json['isActive']),
  );
}
