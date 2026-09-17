import '../../workstreams/domain/workstream.dart';
import 'product_attribute.dart';
import 'product_image.dart';
import 'product_status.dart';

/// The `{id, name, workstreamId, workstream}` the backend embeds on a
/// product for its category — not the full `Category` (see
/// `features/categories/domain/category.dart`). A product has no
/// workstream of its own; it's implied by its category's, carried here so
/// screens don't need a second lookup just to show it.
class ProductCategoryRef {
  const ProductCategoryRef({required this.id, required this.name, required this.workstreamId, this.workstream});

  final String id;
  final String name;
  final String workstreamId;
  final WorkstreamRef? workstream;

  factory ProductCategoryRef.fromJson(Map<String, dynamic> json) => ProductCategoryRef(
    id: json['id'] as String,
    name: json['name'] as String,
    workstreamId: json['workstreamId'] as String,
    workstream: json['workstream'] != null
        ? WorkstreamRef.fromJson(json['workstream'] as Map<String, dynamic>)
        : null,
  );
}

/// Mirrors the backend's `Product` model (`GET/POST/PATCH/DELETE /products`)
/// — field names match the API's camelCase JSON exactly, per ARCHITECTURE.md
/// §E's `products` table (`sku, name, description, category_id,
/// selling_price, cost_price, uom, min_stock_level, status`).
///
/// Prisma `Decimal` fields serialize as JSON strings, not numbers — [_num]
/// parses either representation defensively rather than assuming one.
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    required this.categoryId,
    this.category,
    required this.sellingPrice,
    this.costPrice,
    required this.uom,
    required this.minStockLevel,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.images = const [],
    this.attributes = const [],
  });

  final String id;
  final String sku;
  final String name;
  final String? description;
  final String categoryId;
  final ProductCategoryRef? category;
  final double sellingPrice;
  final double? costPrice;
  final String uom;
  final double minStockLevel;
  final ProductStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProductImage> images;
  final List<ProductAttribute> attributes;

  /// The image flagged `isPrimary`, falling back to the first image when
  /// none is explicitly marked (matches how the backend orders `images` by
  /// `sortOrder`).
  ProductImage? get primaryImage {
    for (final image in images) {
      if (image.isPrimary) return image;
    }
    return images.isEmpty ? null : images.first;
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    categoryId: json['categoryId'] as String,
    category: json['category'] != null
        ? ProductCategoryRef.fromJson(json['category'] as Map<String, dynamic>)
        : null,
    sellingPrice: _num(json['sellingPrice'])!,
    costPrice: _num(json['costPrice']),
    uom: json['uom'] as String,
    minStockLevel: _num(json['minStockLevel']) ?? 0,
    status: ProductStatus.fromJson(json['status'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    images: (json['images'] as List<dynamic>? ?? const [])
        .map((e) => ProductImage.fromJson(e as Map<String, dynamic>))
        .toList(),
    attributes: (json['attributes'] as List<dynamic>? ?? const [])
        .map((e) => ProductAttribute.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

double? _num(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.parse(value as String);
}
