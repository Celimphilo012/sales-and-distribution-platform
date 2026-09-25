/// A single product image entry — either an external link ([url]) or a
/// file uploaded from device storage ([hasFile], fetched via the
/// authenticated `GET /products/:productId/images/:id/file` endpoint since
/// it isn't a directly-reachable public URL). Exactly one of the two is set,
/// mirrored by `product_images` (`GET/POST/POST .../upload/PATCH/DELETE
/// /products/:id/images`).
class ProductImage {
  const ProductImage({
    required this.id,
    required this.productId,
    required this.url,
    required this.hasFile,
    required this.sortOrder,
    required this.isPrimary,
  });

  final String id;
  final String productId;
  final String? url;
  final bool hasFile;
  final int sortOrder;
  final bool isPrimary;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
    id: json['id'] as String,
    productId: json['productId'] as String,
    url: json['url'] as String?,
    hasFile: json['storagePath'] != null,
    sortOrder: json['sortOrder'] as int,
    isPrimary: json['isPrimary'] as bool,
  );
}
