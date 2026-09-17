import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_dropdown_field.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/app_tree_view.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../../warehouses/data/warehouses_providers.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/locations_providers.dart';
import '../../domain/location.dart';
import '../../domain/location_tree.dart';

T? _firstOrNull<T>(Iterable<T> iterable) {
  final iterator = iterable.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

/// Stock can only be held at LEAF locations (§ rule 5 / backend `assertLeaf`,
/// enforced on every receiving/transfer/count/adjustment call). This is the
/// ONE reusable picker every stock-moving screen uses to choose a
/// destination/source: it shows the full tree (reusing 6c's
/// `warehouseLocationsProvider`/`warehouseLocationTreeProvider`, which needs
/// only `warehouse.structure.view` — not `.manage` — so warehouse staff can
/// use it) but only LEAF nodes are selectable. Non-leaf nodes render dimmed
/// and inert — visible for navigation/context, never tappable — mirroring
/// the backend's own constraint instead of letting the user pick an invalid
/// location and only finding out from a 400 after submitting.
///
/// [excludeLocationId], when set, also dims and disables that one leaf (used
/// by the transfer form so the FROM and TO pickers can't both land on the
/// same location — the backend rejects that too, but this catches it before
/// the round trip).
Future<Location?> showLeafLocationPicker(
  BuildContext context, {
  String title = 'Choose a location',
  String? excludeLocationId,
  String? initialWarehouseId,
}) {
  return showDialog<Location>(
    context: context,
    builder: (context) => _LeafLocationPickerDialog(
      title: title,
      excludeLocationId: excludeLocationId,
      initialWarehouseId: initialWarehouseId,
    ),
  );
}

class _LeafLocationPickerDialog extends ConsumerStatefulWidget {
  const _LeafLocationPickerDialog({
    required this.title,
    required this.excludeLocationId,
    required this.initialWarehouseId,
  });

  final String title;
  final String? excludeLocationId;
  final String? initialWarehouseId;

  @override
  ConsumerState<_LeafLocationPickerDialog> createState() => _LeafLocationPickerDialogState();
}

class _LeafLocationPickerDialogState extends ConsumerState<_LeafLocationPickerDialog> {
  String? _warehouseId;
  bool _includeInactive = false;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.initialWarehouseId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehousesAsync = ref.watch(warehousesProvider(false));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              warehousesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(
                  error is AppError ? error.message : 'Could not load warehouses.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                data: (warehouses) {
                  if (warehouses.isEmpty) {
                    return const EmptyStateView(title: 'No active warehouses', icon: Icons.warehouse_outlined);
                  }
                  _warehouseId ??= warehouses.first.id;
                  final selected = _firstOrNull(warehouses.where((w) => w.id == _warehouseId)) ?? warehouses.first;
                  return AppDropdownField<Warehouse>(
                    label: 'Warehouse',
                    value: selected,
                    items: warehouses,
                    itemLabel: (w) => '${w.name} (${w.code})',
                    onChanged: (w) => setState(() => _warehouseId = w?.id),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Search',
                controller: _searchController,
                hintText: 'Name or code',
                prefixIcon: Icons.search,
                onChanged: (value) => setState(() => _search = value),
              ),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _includeInactive,
                onSelected: (value) => setState(() => _includeInactive = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: _warehouseId == null
                    ? const SizedBox.shrink()
                    : _LeafTree(
                        key: ValueKey('$_warehouseId-$_includeInactive'),
                        warehouseId: _warehouseId!,
                        includeInactive: _includeInactive,
                        search: _search,
                        excludeLocationId: widget.excludeLocationId,
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeafTree extends ConsumerWidget {
  const _LeafTree({
    super.key,
    required this.warehouseId,
    required this.includeInactive,
    required this.search,
    required this.excludeLocationId,
  });

  final String warehouseId;
  final bool includeInactive;
  final String search;
  final String? excludeLocationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (warehouseId: warehouseId, includeInactive: includeInactive);
    final treeAsync = ref.watch(warehouseLocationTreeProvider(args));

    return treeAsync.when(
      loading: () => const LoadingStateView(message: 'Loading locations…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load locations.',
        onRetry: () => ref.invalidate(warehouseLocationsProvider(args)),
      ),
      data: (tree) {
        final filtered = filterLocationTree(tree, search);
        if (filtered.isEmpty) {
          return const EmptyStateView(title: 'No locations found', icon: Icons.account_tree_outlined);
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: AppTreeView<LocationNode>(
              roots: filtered,
              childrenOf: (node) => node.children,
              idOf: (node) => node.location.id,
              contentBuilder: (context, node, {required isSelected}) => _LeafPickerRow(
                node: node,
                excluded: node.location.id == excludeLocationId,
                onPick: (location) => Navigator.of(context, rootNavigator: true).pop(location),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LeafPickerRow extends StatelessWidget {
  const _LeafPickerRow({required this.node, required this.excluded, required this.onPick});

  final LocationNode node;
  final bool excluded;
  final ValueChanged<Location> onPick;

  bool get _isLeaf => node.children.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = node.location;
    final selectable = _isLeaf && !excluded;

    final dimColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            _isLeaf ? Icons.label_outline : Icons.folder_outlined,
            size: 18,
            color: selectable ? theme.colorScheme.onSurfaceVariant : dimColor,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: location.name,
                    style: theme.textTheme.bodyMedium?.copyWith(color: selectable ? null : dimColor),
                  ),
                  TextSpan(
                    text: '  ${location.code} · ${location.locationType}',
                    style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
                  ),
                  if (!_isLeaf)
                    TextSpan(text: '  — not a leaf location', style: theme.textTheme.bodySmall?.copyWith(color: dimColor))
                  else if (excluded)
                    TextSpan(
                      text: '  — already chosen for the other side',
                      style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!location.isActive) const StatusChip(),
        ],
      ),
    );

    if (!selectable) return row;
    return InkWell(
      onTap: () => onPick(location),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: row,
    );
  }
}

/// Tiny inline "Inactive" marker — not the full [StatusBadge] pill, to keep
/// picker rows compact.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        'Inactive',
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
      ),
    );
  }
}
