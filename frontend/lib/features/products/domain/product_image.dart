/// A single product image entry — URL-only this phase (no file upload).
/// Mirrors `product_images` (`GET/POST/PATCH/DELETE /products/:id/images`).
class ProductImage {
  const ProductImage({
    required this.id,
    required this.productId,
    required this.url,
    required this.sortOrder,
    required this.isPrimary,
  });

  final String id;
  final String productId;
  final String url;
  final int sortOrder;
  final bool isPrimary;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
    id: json['id'] as String,
    productId: json['productId'] as String,
    url: json['url'] as String,
    sortOrder: json['sortOrder'] as int,
    isPrimary: json['isPrimary'] as bool,
  );
}
