import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../users/data/users_providers.dart';
import '../../users/domain/user.dart';
import '../data/workstream_managers_providers.dart';
import '../domain/workstream.dart';
import '../domain/workstream_manager.dart';

/// Who can manage a workstream's catalogue (categories + products) — the
/// admin-side UI for `WorkstreamManagersController` (`workstreams.assign`).
/// Assigning someone here is what actually scopes them; the
/// WORKSTREAM_MANAGER role (Roles screen) just bundles the permissions
/// (`catalogue.view` + `products.manage`) they need to act on it.
Future<void> showWorkstreamManagersDialog(BuildContext context, Workstream workstream) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WorkstreamManagersDialog(workstream: workstream),
  );
}

class _WorkstreamManagersDialog extends ConsumerStatefulWidget {
  const _WorkstreamManagersDialog({required this.workstream});

  final Workstream workstream;

  @override
  ConsumerState<_WorkstreamManagersDialog> createState() => _WorkstreamManagersDialogState();
}

class _WorkstreamManagersDialogState extends ConsumerState<_WorkstreamManagersDialog> {
  String? _selectedUserId;
  bool _saving = false;
  String? _error;

  Future<void> _assign() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(workstreamManagersApiProvider).assign(widget.workstream.id, userId);
      setState(() => _selectedUserId = null);
      ref.invalidate(workstreamManagersProvider(widget.workstream.id));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unassign(WorkstreamManager manager) async {
    try {
      await ref.read(workstreamManagersApiProvider).unassign(widget.workstream.id, manager.userId);
      ref.invalidate(workstreamManagersProvider(widget.workstream.id));
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final managersAsync = ref.watch(workstreamManagersProvider(widget.workstream.id));
    final usersAsync = ref.watch(usersListProvider);

    return AppDialog(
      title: 'Managers — ${widget.workstream.name}',
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A user assigned here can manage this workstream\'s categories and products — '
              'and ONLY this workstream\'s, once assigned (see CLAUDE.md). They still need the '
              'catalogue.view + products.manage permissions themselves (the WORKSTREAM_MANAGER '
              'role bundles both).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            managersAsync.when(
              loading: () => const LoadingStateView(message: 'Loading managers…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load managers.',
                onRetry: () => ref.invalidate(workstreamManagersProvider(widget.workstream.id)),
              ),
              data: (managers) {
                if (managers.isEmpty) {
                  return Text(
                    'No managers assigned yet — everyone with products.manage can edit this '
                    'workstream\'s catalogue.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  );
                }
                return Column(
                  children: [
                    for (final manager in managers)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(manager.userFullName),
                        subtitle: Text(manager.userEmail),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Unassign',
                          onPressed: () => _unassign(manager),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            usersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (users) {
                final assignedIds = (managersAsync.value ?? const []).map((m) => m.userId).toSet();
                final candidates = users
                    .where((u) => u.status == UserStatus.active && !assignedIds.contains(u.id))
                    .toList();
                if (candidates.isEmpty) {
                  return Text(
                    'No more active users to assign.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppDropdownField<String?>(
                        label: 'Assign a user',
                        value: _selectedUserId,
                        items: [for (final u in candidates) u.id],
                        itemLabel: (id) {
                          final u = candidates.firstWhere((u) => u.id == id);
                          return '${u.fullName} (${u.email})';
                        },
                        onChanged: (value) => setState(() => _selectedUserId = value),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: FilledButton(
                        onPressed: (_selectedUserId == null || _saving) ? null : _assign,
                        child: Text(_saving ? 'Adding…' : 'Add'),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
