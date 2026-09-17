import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/app_tree_view.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../locations/data/locations_providers.dart';
import '../../locations/domain/location.dart';
import '../../locations/domain/location_path.dart';
import '../../locations/domain/location_tree.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import 'widgets/location_stock_panel.dart';

T? _firstOrNull<T>(Iterable<T> iterable) {
  final iterator = iterable.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

/// "What's in this location?" — pick a location (by warehouse, then its
/// tree — the same tree data 6c uses), then show every product balanced
/// there. Read-only: no add/edit/move/deactivate actions, unlike 6c's own
/// tree panel.
class WhatsInThisLocationView extends ConsumerStatefulWidget {
  const WhatsInThisLocationView({super.key});

  @override
  ConsumerState<WhatsInThisLocationView> createState() => _WhatsInThisLocationViewState();
}

class _WhatsInThisLocationViewState extends ConsumerState<WhatsInThisLocationView> {
  Location? _selected;

  @override
  Widget build(BuildContext context) {
    if (_selected == null) {
      return _LocationPicker(onSelected: (location) => setState(() => _selected = location));
    }
    return _LocationBreakdown(location: _selected!, onChangeLocation: () => setState(() => _selected = null));
  }
}

class _LocationPicker extends ConsumerStatefulWidget {
  const _LocationPicker({required this.onSelected});

  final ValueChanged<Location> onSelected;

  @override
  ConsumerState<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<_LocationPicker> {
  String? _warehouseId;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehousesAsync = ref.watch(warehousesProvider(false));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick a location', style: theme.textTheme.titleMedium),
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
                onChanged: (w) => setState(() => _warehouseId = w?.id),
              ),
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
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _warehouseId == null
              ? const SizedBox.shrink()
              : _LocationTreePicker(
                  key: ValueKey(_warehouseId),
                  warehouseId: _warehouseId!,
                  search: _search,
                  onSelected: widget.onSelected,
                ),
        ),
      ],
    );
  }
}

class _LocationTreePicker extends ConsumerWidget {
  const _LocationTreePicker({super.key, required this.warehouseId, required this.search, required this.onSelected});

  final String warehouseId;
  final String search;
  final ValueChanged<Location> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (warehouseId: warehouseId, includeInactive: false);
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
              contentBuilder: (context, node, {required isSelected}) => _PickerRow(
                node: node,
                onTap: () => onSelected(node.location),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.node, required this.onTap});

  final LocationNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = node.location;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
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
            if (!location.isActive) const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
          ],
        ),
      ),
    );
  }
}

class _LocationBreakdown extends ConsumerWidget {
  const _LocationBreakdown({required this.location, required this.onChangeLocation});

  final Location location;
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Reuses 6c's per-warehouse location fetch (location_path.dart resolves
    // the ancestor chain from it) plus the warehouse list, for the same
    // full "Warehouse → ... → Bin" breadcrumb the product-centric view shows.
    final locationsAsync = ref.watch(
      warehouseLocationsProvider((warehouseId: location.warehouseId, includeInactive: true)),
    );
    final warehousesAsync = ref.watch(warehousesProvider(true));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_breadcrumb(locationsAsync, warehousesAsync), style: theme.textTheme.titleLarge),
                  Text(
                    '${location.code} · ${location.locationType}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onChangeLocation,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Change location'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(child: LocationStockPanel(locationId: location.id)),
      ],
    );
  }

  String _breadcrumb(AsyncValue<List<Location>> locationsAsync, AsyncValue<List<Warehouse>> warehousesAsync) {
    final all = locationsAsync.value;
    final warehouses = warehousesAsync.value;
    if (all == null) return location.name;

    final path = locationPath(all, location.id);
    final warehouseName = _firstOrNull(
      warehouses?.where((w) => w.id == location.warehouseId) ?? const <Warehouse>[],
    )?.name;

    return [?warehouseName, ...path.map((l) => l.name)].join(' › ');
  }
}
