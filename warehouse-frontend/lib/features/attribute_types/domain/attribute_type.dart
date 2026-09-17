import '../../../shared/json_utils.dart';

/// Mirrors the backend's `AttributeDataType` enum — governs how a value for
/// this type is entered/validated/displayed (a number field vs a text
/// field), never a second storage column: every value is still stored (and
/// read back) as a string.
enum AttributeDataType {
  text,
  number;

  factory AttributeDataType.fromJson(String value) => switch (value) {
    'NUMBER' => AttributeDataType.number,
    _ => AttributeDataType.text,
  };

  String toJson() => switch (this) {
    AttributeDataType.text => 'TEXT',
    AttributeDataType.number => 'NUMBER',
  };
}

/// Mirrors the backend's `AttributeType` model (`GET/POST/PATCH/DELETE
/// /attribute-types`) — the admin-managed catalog behind product
/// attributes. Adding a new one (e.g. "Country of Origin") is how the
/// attribute model stays extensible without a frontend/backend code
/// change: the product form picks up new active types automatically.
class AttributeType {
  const AttributeType({
    required this.id,
    required this.name,
    required this.code,
    required this.dataType,
    this.unit,
    required this.isActive,
  });

  final String id;
  final String name;
  final String code;
  final AttributeDataType dataType;
  final String? unit;
  final bool isActive;

  factory AttributeType.fromJson(Map<String, dynamic> json) => AttributeType(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    dataType: AttributeDataType.fromJson(json['dataType'] as String),
    unit: json['unit'] as String?,
    isActive: boolFromJson(json['isActive']),
  );
}
