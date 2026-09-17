import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../domain/api_key.dart';

/// Shows a freshly created key's raw value EXACTLY ONCE, per the step-3
/// mechanism (ARCHITECTURE.md §A2: "raw key stored only as an argon2 hash —
/// shown once at creation"). Not dismissible by tapping outside or the back
/// button — the only way out is the explicit "I've copied it" button, so a
/// stray tap can't lose it unacknowledged. The value never touches any
/// provider/cache; it lives only in this dialog's own build.
Future<void> showRawApiKeyDialog(BuildContext context, ApiKeyCreated created) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(canPop: false, child: _RawApiKeyDialog(created: created)),
  );
}

class _RawApiKeyDialog extends StatelessWidget {
  const _RawApiKeyDialog({required this.created});

  final ApiKeyCreated created;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;

    return AppDialog(
      title: '"${created.record.name}" created',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: semantic.warningContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_outlined, color: semantic.onWarningContainer, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Copy this key now — you will not be able to see it again. Only a hash is '
                    'stored; if you lose it, revoke this key and create a new one.',
                    style: theme.textTheme.bodySmall?.copyWith(color: semantic.onWarningContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: SelectableText(
              created.rawKey,
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: created.rawKey));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text("I've copied it — close"),
        ),
      ],
    );
  }
}
