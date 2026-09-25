import 'package:flutter/material.dart';

/// A pasted image URL might not load (typo, dead link, slow network) — this
/// renders a themed placeholder for the loading and error states instead of
/// leaving a blank box or an uncaught exception.
class NetworkImageOrPlaceholder extends StatelessWidget {
  const NetworkImageOrPlaceholder({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
