import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/authenticated_image_or_placeholder.dart';
import '../../../../shared/widgets/network_image_or_placeholder.dart';
import '../../data/workstreams_providers.dart';
import '../../domain/workstream.dart';

/// Renders a [Workstream]'s image regardless of whether it's a pasted URL
/// (plain `Image.network`) or a file uploaded from device storage
/// (authenticated bytes fetch) — mirrors the products feature's own
/// `ProductImageView`.
class WorkstreamImageView extends ConsumerWidget {
  const WorkstreamImageView({super.key, required this.workstream, this.fit = BoxFit.cover});

  final Workstream workstream;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!workstream.hasImageFile) return NetworkImageOrPlaceholder(url: workstream.imageUrl!);
    final bytesAsync = ref.watch(workstreamImageFileProvider(workstream.id));
    return AuthenticatedImageOrPlaceholder(bytes: bytesAsync, fit: fit);
  }
}
