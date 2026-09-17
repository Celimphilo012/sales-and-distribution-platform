import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';
import '../domain/location_tree.dart';

const _rootSentinel = '__root__';

/// Reparent [location] within its own warehouse's already-loaded [tree].
/// Moving a node moves its whole subtree with it (children keep pointing at
/// the same `parentId`, so nothing else has to change). The picker EXCLUDES
/// the node itself and every one of its descendants client-side
/// (`locationDescendantIds` — the same check the backend's own
/// `assertNoCycle` performs), so the common mistake is impossible to even
/// select; the backend is still the real guard and its message (409 for a
/// cycle it catches anyway, 400 for a self-parent) surfaces cleanly if it
/// ever disagrees.
Future<void> showMoveLocationDialog(
  BuildContext context, {
  required Location location,
  required List<LocationNode> tree,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MoveLocationDialog(location: location, tree: tree),
  );
}

class _MoveLocationDialog extends ConsumerStatefulWidget {
  const _MoveLocationDialog({required this.location, required this.tree});

  final Location location;
  final List<LocationNode> tree;

  @override
  ConsumerState<_MoveLocationDialog> createState() => _MoveLocationDialogState();
}

class _MoveLocationDialogState extends ConsumerState<_MoveLocationDialog> {
  late String _target;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _target = widget.location.parentId ?? _rootSentinel;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(locationsApiProvider)
          .move(widget.location.id, newParentId: _target == _rootSentinel ? null : _target);
      invalidateWarehouseLocations(ref, widget.location.warehouseId);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final excluded = locationDescendantIds(widget.tree, widget.location.id);
    final options = flattenLocationTree(widget.tree).where((n) => !excluded.contains(n.location.id)).toList();
    final noChange = _target == (widget.location.parentId ?? _rootSentinel);

    return AppDialog(
      title: 'Move "${widget.location.name}"',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Moving this location moves everything under it too.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDropdownField<String>(
            label: 'New parent',
            value: _target,
            items: [_rootSentinel, for (final node in options) node.location.id],
            itemLabel: (id) {
              if (id == _rootSentinel) return 'None — top level of this warehouse';
              final node = options.firstWhere((n) => n.location.id == id);
              return '${'    ' * node.depth}${node.location.name} (${node.location.code})';
            },
            onChanged: (value) => setState(() => _target = value ?? _target),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || noChange) ? null : _save,
          child: Text(_saving ? 'Moving…' : 'Move'),
        ),
      ],
    );
  }
}
