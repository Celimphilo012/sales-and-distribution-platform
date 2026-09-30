import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_format.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../../users/data/users_providers.dart';
import '../../data/api_keys_providers.dart';
import '../../domain/api_key.dart';
import 'create_api_key_dialog.dart';
import 'raw_api_key_dialog.dart';
import 'settings_head.dart';

/// API keys (`users.manage`): scoped keys the back-office uses to call this
/// warehouse. The raw key is shown once.
class ApiKeysSection extends ConsumerWidget {
  const ApiKeysSection({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showCreateApiKeyDialog(context);
    if (created == null) return;
    ref.invalidate(apiKeysListProvider);
    if (context.mounted) await showRawApiKeyDialog(context, created);
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, ApiKeyRecord key) async {
    final ok = await showNxConfirm(
      context,
      title: 'Revoke "${key.name}"?',
      body: 'Any caller still using this key will be rejected immediately.',
      confirmLabel: 'Revoke',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(apiKeysApiProvider).revoke(key.id);
      ref.invalidate(apiKeysListProvider);
      NxToast.ok('API key revoked', key.name);
    } on AppError catch (e) {
      NxToast.error('Not revoked', e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final keys = ref.watch(apiKeysListProvider);
    final users = {for (final u in ref.watch(usersListProvider).value ?? const []) u.id: u.fullName};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHead(
          'API keys',
          sub: 'Scoped keys the back-office uses to call this warehouse. The raw key is shown once.',
          trailing: NxButton.primary(label: 'New key', icon: PhosphorIconsRegular.key, onPressed: () => _create(context, ref)),
        ),
        keys.when(
          loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => Text(e is AppError ? e.message : 'Could not load API keys.', style: TextStyle(fontSize: 12, color: n.bad)),
          data: (list) => list.isEmpty
              ? Text('No API keys yet.', style: TextStyle(fontSize: 12, color: n.n400))
              : Column(
                  children: [
                    for (final k in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.md), border: Border.all(color: n.divider)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(child: Text(k.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text))),
                                        const SizedBox(width: 8),
                                        NxTag(k.isActive ? 'Active' : 'Revoked', small: true, tone: k.isActive ? Tone.ok : Tone.neutral),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(spacing: 4, runSpacing: 4, children: [for (final s in k.scopes) NxTag(s, small: true, mono: true)]),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Created ${fmtDateTime(k.createdAt.toLocal())}${users[k.createdBy] == null ? '' : ' by ${users[k.createdBy]}'}'
                                      ' · last used ${k.lastUsedAt == null ? 'never' : fmtWhen(k.lastUsedAt)}',
                                      style: TextStyle(fontSize: 11, color: n.n500),
                                    ),
                                  ],
                                ),
                              ),
                              if (k.isActive) NxButton(label: 'Revoke', small: true, color: n.bad, onPressed: () => _revoke(context, ref, k)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
