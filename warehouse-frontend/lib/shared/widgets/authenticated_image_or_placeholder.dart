import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Like [NetworkImageOrPlaceholder] but for an image that must be fetched
/// with an authenticated request instead of loaded as a plain public URL —
/// a file uploaded from device storage (a product image, a workstream
/// image, ...) is served from this app's own backend behind a permission
/// guard, not a directly-reachable link. [bytes] is the already-watched
/// [AsyncValue] from the caller's own Riverpod family provider (each
/// feature keeps one, e.g. `productImageFileProvider`, mirroring the
/// stock-adjustments feature's `adjustmentPhotoProvider`) — a plain
/// [AsyncValue] rather than the provider itself, since `ProviderListenable`
/// isn't part of `flutter_riverpod`'s public API in this version.
class AuthenticatedImageOrPlaceholder extends StatelessWidget {
  const AuthenticatedImageOrPlaceholder({super.key, required this.bytes, this.fit = BoxFit.cover});

  final AsyncValue<Uint8List> bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return bytes.when(
      loading: () => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (error, stackTrace) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
      ),
      data: (data) => Image.memory(data, fit: fit),
    );
  }
}
