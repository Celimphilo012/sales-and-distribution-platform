import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/app_tree_view.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../inventory/presentation/widgets/location_stock_panel.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';
import '../domain/location_tree.dart';
import 'generate_levels_dialog.dart';
import 'location_form_dialog.dart';
import 'move_location_dialog.dart';

/// Dart's core `Iterable` has no `firstOrNull` — this avoids pulling in
/// `package:collection` (a transitive dep only) for one-line uses.
T? _firstOrNull<T>(Iterable<T> iterable) {
  final iterator = iterable.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

/// The core 6c screen: pick a warehouse, see its full location tree
/// (`GET /locations/:id/subtree` per root, unlimited depth), select a node
/// for its detail panel, and — permission-gated — add/rename/move/
/// deactivate right from the tree.
class WarehouseStructureScreen extends ConsumerStatefulWidget {
  const WarehouseStructureScreen({super.key, this.initialWarehouseId});

  final String? initialWarehouseId;

  @override
  ConsumerState<WarehouseStructureScreen> createState() => _WarehouseStructureScreenState();
}

class _WarehouseStructureScreenState extends ConsumerState<WarehouseStructureScreen> {
  String? _warehouseId;
  String? _selectedLocationId;
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Warehouse Structure', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          warehousesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(
              error is AppError ? error.message : 'Could not load warehouses.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            data: (warehouses) {
              if (warehouses.isEmpty) {
                return const EmptyStateView(
                  title: 'No active warehouses',
                  message: 'Create a warehouse first, from the Warehouses screen.',
                  icon: Icons.warehouse_outlined,
                );
              }
              _warehouseId ??= warehouses.first.id;
              final selected = _firstOrNull(warehouses.where((w) => w.id == _warehouseId)) ?? warehouses.first;
              return SizedBox(
                width: 320,
                child: AppDropdownField<Warehouse>(
                  label: 'Warehouse',
                  value: selected,
                  items: warehouses,
                  itemLabel: (w) => '${w.name} (${w.code})',
                  onChanged: (w) => setState(() {
                    _warehouseId = w?.id;
                    _selectedLocationId = null;
                  }),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _warehouseId == null
                ? const SizedBox.shrink()
                : _WarehouseStructureBody(
                    key: ValueKey(_warehouseId),
                    warehouseId: _warehouseId!,
                    includeInactive: _includeInactive,
                    onIncludeInactiveChanged: (value) => setState(() => _includeInactive = value),
                    searchController: _searchController,
                    search: _search,
                    onSearchChanged: (value) => setState(() => _search = value),
                    selectedLocationId: _selectedLocationId,
                    onSelect: (id) => setState(() => _selectedLocationId = id),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseStructureBody extends ConsumerWidget {
  const _WarehouseStructureBody({
    super.key,
    required this.warehouseId,
    required this.includeInactive,
    required this.onIncludeInactiveChanged,
    required this.searchController,
    required this.search,
    required this.onSearchChanged,
    required this.selectedLocationId,
    required this.onSelect,
  });

  final String warehouseId;
  final bool includeInactive;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final TextEditingController searchController;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final String? selectedLocationId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(
      authProvider.select((s) => s.value?.user?.can('warehouse.structure.manage') ?? false),
    );
    final args = (warehouseId: warehouseId, includeInactive: includeInactive);
    final treeAsync = ref.watch(warehouseLocationTreeProvider(args));

    return treeAsync.when(
      loading: () => const LoadingStateView(message: 'Loading location tree…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load the location tree.',
        onRetry: () => ref.invalidate(warehouseLocationsProvider(args)),
      ),
      data: (tree) {
        final filtered = filterLocationTree(tree, search);
        final flat = flattenLocationTree(tree);
        final selected = selectedLocationId == null
            ? null
            : _firstOrNull(flat.where((n) => n.location.id == selectedLocationId))?.location;

        final treePanel = _TreePanel(
          warehouseId: warehouseId,
          tree: filtered,
          fullTree: tree,
          canManage: canManage,
          includeInactive: includeInactive,
          onIncludeInactiveChanged: onIncludeInactiveChanged,
          searchController: searchController,
          onSearchChanged: onSearchChanged,
          selectedLocationId: selectedLocationId,
          onSelect: onSelect,
        );

        return ResponsiveLayout(
          mobile: (context) => treePanel,
          desktop: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: treePanel),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 4,
                child: selected == null
                    ? const AppCard(
                        child: EmptyStateView(
                          title: 'No location selected',
                          message: 'Select a location in the tree to see its details.',
                          icon: Icons.info_outline,
                        ),
                      )
                    : _LocationDetailPanel(location: selected, canManage: canManage, tree: tree),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TreePanel extends StatelessWidget {
  const _TreePanel({
    required this.warehouseId,
    required this.tree,
    required this.fullTree,
    required this.canManage,
    required this.includeInactive,
    required this.onIncludeInactiveChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedLocationId,
    required this.onSelect,
  });

  final String warehouseId;
  final List<LocationNode> tree;
  final List<LocationNode> fullTree;
  final bool canManage;
  final bool includeInactive;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? selectedLocationId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                label: 'Search',
                controller: searchController,
                hintText: 'Name or code',
                prefixIcon: Icons.search,
                onChanged: onSearchChanged,
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add root location',
                onPressed: () => showLocationFormDialog(context, warehouseId: warehouseId),
              ),
            ],
          ],
        ),
        FilterChip(
          label: const Text('Show inactive'),
          selected: includeInactive,
          onSelected: onIncludeInactiveChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: tree.isEmpty
              ? const EmptyStateView(title: 'No locations found', icon: Icons.account_tree_outlined)
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: AppTreeView<LocationNode>(
                      roots: tree,
                      childrenOf: (node) => node.children,
                      idOf: (node) => node.location.id,
                      selectedId: selectedLocationId,
                      contentBuilder: (context, node, {required isSelected}) => _LocationRow(
                        node: node,
                        fullTree: fullTree,
                        canManage: canManage,
                        isSelected: isSelected,
                        onTap: () => onSelect(node.location.id),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LocationRow extends ConsumerWidget {
  const _LocationRow({
    required this.node,
    required this.fullTree,
    required this.canManage,
    required this.isSelected,
    required this.onTap,
  });

  final LocationNode node;
  final List<LocationNode> fullTree;
  final bool canManage;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = node.location;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.4) : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              node.children.isEmpty ? Icons.label_outline : Icons.folder_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: location.name, style: theme.textTheme.bodyMedium),
                    TextSpan(
                      text: '  ${location.code} · ${location.locationType}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!location.isActive) ...[
              const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (canManage)
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (action) => _handleAction(context, ref, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'add_child', child: Text('Add child location')),
                  const PopupMenuItem(value: 'generate_levels', child: Text('Create levels…')),
                  const PopupMenuItem(value: 'edit', child: Text('Rename / edit')),
                  const PopupMenuItem(value: 'move', child: Text('Move…')),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Text(location.isActive ? 'Deactivate' : 'Reactivate'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    final location = node.location;
    switch (action) {
      case 'add_child':
        await showLocationFormDialog(
          context,
          warehouseId: location.warehouseId,
          parentId: location.id,
          parentType: location.locationType,
        );
      case 'generate_levels':
        await showGenerateLevelsDialog(context, parent: location);
      case 'edit':
        await showLocationFormDialog(context, location: location);
      case 'move':
        await showMoveLocationDialog(context, location: location, tree: fullTree);
      case 'toggle_active':
        if (location.isActive) {
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Deactivate location?',
            message:
                'This marks "${location.name}" inactive. It is NOT deleted, and its child locations (if '
                'any) are NOT automatically deactivated — they stay as they are, just nested under an '
                'inactive parent.',
            confirmLabel: 'Deactivate',
            isDestructive: true,
          );
          if (!confirmed) return;
          try {
            await ref.read(locationsApiProvider).deactivate(location.id);
            invalidateWarehouseLocations(ref, location.warehouseId);
          } on AppError catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        } else {
          try {
            await ref.read(locationsApiProvider).reactivate(location.id);
            invalidateWarehouseLocations(ref, location.warehouseId);
          } on AppError catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
    }
  }
}

class _LocationDetailPanel extends StatelessWidget {
  const _LocationDetailPanel({required this.location, required this.canManage, required this.tree});

  final Location location;
  final bool canManage;
  final List<LocationNode> tree;

  @override
  Widget build(BuildContext context) {
    final parent = location.parentId == null
        ? null
        : _firstOrNull(flattenLocationTree(tree).where((n) => n.location.id == location.parentId))?.location;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            title: location.name,
            trailing: StatusBadge(
              label: location.isActive ? 'Active' : 'Inactive',
              tone: location.isActive ? StatusTone.success : StatusTone.neutral,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Code', value: location.code),
                _DetailRow(label: 'Type', value: location.locationType),
                _DetailRow(label: 'Parent', value: parent == null ? '— (top level)' : '${parent.name} (${parent.code})'),
                _DetailRow(
                  label: 'Description',
                  value: (location.description?.isNotEmpty ?? false) ? location.description! : '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            title: 'Stock in this location',
            child: LocationStockPanel(locationId: location.id),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
