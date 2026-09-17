import '../../attribute_types/domain/attribute_type.dart';

/// A single {attribute type, value} pair on a product — descriptive
/// metadata only (colour, size, weight, ...), NOT a variant: stock stays
/// keyed by product+location regardless of any attribute value. Mirrors
/// the backend's `ProductAttribute` model, always nested with its full
/// `attributeType` (never just the id) so screens never need a second
/// lookup to know a value's label/dataType/unit.
class ProductAttribute {
  const ProductAttribute({required this.id, required this.attributeTypeId, required this.value, required this.attributeType});

  final String id;
  final String attributeTypeId;
  final String value;
  final AttributeType attributeType;

  factory ProductAttribute.fromJson(Map<String, dynamic> json) => ProductAttribute(
    id: json['id'] as String,
    attributeTypeId: json['attributeTypeId'] as String,
    value: json['value'] as String,
    attributeType: AttributeType.fromJson(json['attributeType'] as Map<String, dynamic>),
  );
}

/// What the create/update API calls send — mirrors the backend's
/// `ProductAttributeInputDto`. [value] is a plain JSON number for a
/// NUMBER-dataType attribute (same "number on write" convention as
/// sellingPrice/costPrice), a string otherwise.
class ProductAttributeInput {
  const ProductAttributeInput({required this.attributeTypeId, required this.value});

  final String attributeTypeId;
  final Object value; // String or num

  Map<String, dynamic> toJson() => {'attributeTypeId': attributeTypeId, 'value': value};
}
