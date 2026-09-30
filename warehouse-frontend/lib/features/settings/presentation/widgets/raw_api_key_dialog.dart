import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../domain/api_key.dart';

/// Shows a new key's raw value EXACTLY ONCE (only a hash is stored). Not
/// dismissible by tapping outside or Back — only the explicit "I've copied
/// it" button closes it, so a stray tap can't lose it.
Future<void> showRawApiKeyDialog(BuildContext context, ApiKeyCreated created) => showNxDialog<void>(
  context,
  dismissible: false,
  builder: (_) => PopScope(canPop: false, child: _RawKey(created: created)),
);

class _RawKey extends StatelessWidget {
  const _RawKey({required this.created});

  final ApiKeyCreated created;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: '"${created.record.name}" created',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: n.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NxRadius.md)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.warning, size: 18, color: n.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Copy this key now — you will not be able to see it again. Only a hash is stored; if you lose it, revoke this key and create a new one.',
                    style: TextStyle(fontSize: 12, color: n.warn),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.md)),
            child: SelectableText(created.rawKey, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: n.text)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: NxButton.ghost(
              label: 'Copy',
              icon: PhosphorIconsRegular.copy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: created.rawKey));
                NxToast.info('Copied to clipboard');
              },
            ),
          ),
        ],
      ),
      actions: [NxButton.primary(label: 'I’ve copied it — close', onPressed: () => Navigator.of(context).pop())],
    );
  }
}
