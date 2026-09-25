import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/authenticated_image_or_placeholder.dart';
import '../../../../shared/widgets/network_image_or_placeholder.dart';
import '../../domain/product_image.dart';
import '../products_list_providers.dart';

/// Renders one [ProductImage] regardless of whether it's a pasted URL
/// (plain `Image.network`) or a file uploaded from device storage
/// (authenticated bytes fetch) — every screen that displays a product image
/// (the images editor, the detail gallery, the products grid) goes through
/// this one branch instead of repeating it three times.
class ProductImageView extends ConsumerWidget {
  const ProductImageView({super.key, required this.image, required this.productId, this.fit = BoxFit.cover});

  final ProductImage image;
  final String productId;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!image.hasFile) return NetworkImageOrPlaceholder(url: image.url!);
    final bytesAsync = ref.watch(productImageFileProvider((productId: productId, imageId: image.id)));
    return AuthenticatedImageOrPlaceholder(bytes: bytesAsync, fit: fit);
  }
}
