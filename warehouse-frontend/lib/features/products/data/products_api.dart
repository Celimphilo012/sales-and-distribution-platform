import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/product.dart';
import '../domain/product_attribute.dart';
import '../domain/product_image.dart';
import '../domain/products_filter.dart';

/// All product + product-image API calls. Feature screens never call
/// [ApiClient] directly — they go through this repository, which owns
/// parsing JSON into domain models. This is the template later features
/// (inventory, orders, ...) copy for their own `data/` layer.
class ProductsApi {
  ProductsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Product>> list(ProductsFilter filter) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<dynamic>>('/products', queryParameters: filter.toQueryParameters()),
    );
    return response.data!.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Product> getById(String id) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/products/$id'));
    return Product.fromJson(response.data!);
  }

  /// `POST /products` — optional fields are omitted from the body entirely
  /// when empty, matching `CreateProductDto`'s `@IsOptional()` fields.
  Future<Product> create({
    required String sku,
    required String name,
    String? description,
    required String categoryId,
    required double sellingPrice,
    double? costPrice,
    required String uom,
    double? minStockLevel,
    List<ProductAttributeInput> attributes = const [],
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/products',
        data: {
          'sku': sku,
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          'categoryId': categoryId,
          'sellingPrice': sellingPrice,
          'costPrice': ?costPrice,
          'uom': uom,
          'minStockLevel': ?minStockLevel,
          'attributes': attributes.map((a) => a.toJson()).toList(),
        },
      ),
    );
    return Product.fromJson(response.data!);
  }

  /// `PATCH /products/:id` — always sends the full editable snapshot (not
  /// sparse diffs), so clearing description/cost price back to empty works
  /// (explicit `null` clears; an omitted key leaves the field untouched
  /// server-side, which a sparse diff can't express for "clear this").
  /// `sku` is intentionally not accepted — the backend's `UpdateProductDto`
  /// has no `sku` field, it's immutable after creation.
  Future<Product> update(
    String id, {
    required String name,
    String? description,
    required String categoryId,
    required double sellingPrice,
    double? costPrice,
    required String uom,
    required double minStockLevel,
    List<ProductAttributeInput> attributes = const [],
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/products/$id',
        data: {
          'name': name,
          'description': description,
          'categoryId': categoryId,
          'sellingPrice': sellingPrice,
          'costPrice': costPrice,
          'uom': uom,
          'minStockLevel': minStockLevel,
          // Always sent (this form always manages the full section) — an
          // empty list deliberately clears every attribute, matching the
          // backend's "provided = replace the full set" semantics.
          'attributes': attributes.map((a) => a.toJson()).toList(),
        },
      ),
    );
    return Product.fromJson(response.data!);
  }

  /// `DELETE /products/:id` — soft-delete: flips status to INACTIVE, never
  /// removes the row (CLAUDE.md rule 10).
  Future<Product> deactivate(String id) async {
    final response = await _apiClient.guard((dio) => dio.delete<Map<String, dynamic>>('/products/$id'));
    return Product.fromJson(response.data!);
  }

  /// Reverses [deactivate] via the same `PATCH` the edit form uses —
  /// `UpdateProductDto` accepts `status`, there's no separate endpoint.
  Future<Product> reactivate(String id) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>('/products/$id', data: {'status': 'ACTIVE'}),
    );
    return Product.fromJson(response.data!);
  }

  Future<ProductImage> addImage(
    String productId, {
    required String url,
    bool isPrimary = false,
    int? sortOrder,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/products/$productId/images',
        data: {'url': url, 'isPrimary': isPrimary, 'sortOrder': ?sortOrder},
      ),
    );
    return ProductImage.fromJson(response.data!);
  }

  /// Same as [addImage], but for a file uploaded from device storage rather
  /// than a pasted URL — `POST /products/:id/images/upload` (multipart).
  Future<ProductImage> addImageUpload(
    String productId, {
    required Uint8List bytes,
    required String fileName,
    bool isPrimary = false,
    int? sortOrder,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/products/$productId/images/upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
          'isPrimary': isPrimary.toString(),
          'sortOrder': ?sortOrder?.toString(),
        }),
      ),
    );
    return ProductImage.fromJson(response.data!);
  }

  /// Fetches an uploaded image's raw bytes (auth attached automatically by
  /// `ApiClient` — NOT a plain public URL `Image.network` could load).
  Future<Uint8List> getImageFileBytes(String productId, String imageId) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<int>>(
        '/products/$productId/images/$imageId/file',
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(response.data!);
  }

  /// The backend enforces single-primary itself (unsetting every other
  /// image on the same product inside a transaction) — this just flips one.
  Future<ProductImage> setImagePrimary(String productId, String imageId) async {
    final response = await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>(
        '/products/$productId/images/$imageId',
        data: {'isPrimary': true},
      ),
    );
    return ProductImage.fromJson(response.data!);
  }

  Future<void> deleteImage(String productId, String imageId) async {
    await _apiClient.guard((dio) => dio.delete('/products/$productId/images/$imageId'));
  }
}
