import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../../warehouse_locations/data/warehouse_locations_providers.dart';
import '../../../warehouse_locations/domain/warehouse_locations.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import 'lifecycle_failure_panel.dart';

/// APPROVED → STOCK_RESERVED — the first action that crosses into the
/// warehouse. The manager says, per order line, which leaf location to
/// reserve from (multi-warehouse pulling is an open decision, so the backend
/// makes the caller explicit), then the backend reserves the whole order in
/// one call.
///
/// The three outcomes stay INSIDE this dialog so nothing is lost:
///  * success            → the dialog closes with `true`;
///  * not enough stock   → the short lines are shown; the order did not move;
///  * warehouse offline  → a "safe to retry" panel; the order did not move.
Future<bool> showReserveStockDialog(BuildContext context, {required Order order}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReserveStockDialog(order: order),
  );
  return result ?? false;
}

class ReserveStockDialog extends ConsumerStatefulWidget {
  const ReserveStockDialog({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<ReserveStockDialog> createState() => _ReserveStockDialogState();
}

class _ReserveStockDialogState extends ConsumerState<ReserveStockDialog> {
  /// order item id → chosen leaf location id.
  final Map<String, String> _locationByItem = {};

  /// Bumped when "reserve all from…" rewrites every line, so the per-line
  /// dropdowns (which only read their initial value) rebuild with it.
  int _selectionVersion = 0;

  bool _busy = false;
  LifecycleFailure? _failure;

  bool get _complete => widget.order.items.every((i) => _locationByItem.containsKey(i.id));

  void _preselectSingleLeaf(WarehouseLocations locations) {
    if (_locationByItem.isNotEmpty) return;
    final leaves = locations.leafLocations;
    if (leaves.length == 1) {
      for (final item in widget.order.items) {
        _locationByItem[item.id] = leaves.first.id;
      }
    }
  }

  Future<void> _reserve() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(ordersApiProvider).reserve(widget.order.id, allocations: Map.of(_locationByItem));
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } on AppError catch (e) {
      if (mounted) setState(() => _failure = classifyLifecycleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locationsAsync = ref.watch(warehouseLocationsProvider);
    final locations = locationsAsync.value;
    if (locations != null) _preselectSingleLeaf(locations);

    return AppDialog(
      title: 'Reserve stock',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose where each line is reserved from. Nothing is reserved until every line has a location '
              'and the warehouse confirms it has the stock.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            locationsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading warehouse locations…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError
                    ? 'Could not load the warehouse locations: ${error.message}'
                    : 'Could not load the warehouse locations.',
                onRetry: () => ref.invalidate(warehouseLocationsProvider),
              ),
              data: (locations) => _form(context, locations),
            ),
            if (_failure != null) ...[
              const SizedBox(height: AppSpacing.md),
              LifecycleFailurePanel(
                failure: _failure!,
                order: widget.order,
                locations: locations,
                onRetry: _busy ? null : _reserve,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || !_complete || locations == null) ? null : _reserve,
          child: Text(_busy ? 'Reserving…' : (_failure == null ? 'Reserve stock' : 'Try again')),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, WarehouseLocations locations) {
    final theme = Theme.of(context);
    final leaves = locations.leafLocations;

    if (leaves.isEmpty) {
      return Text(
        'The warehouse has no active locations to reserve from.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.order.items.length > 1) ...[
          _LocationDropdown(
            key: ValueKey('all-$_selectionVersion'),
            label: 'Reserve every line from…',
            leaves: leaves,
            locations: locations,
            value: _allSame() ? _locationByItem.values.first : null,
            enabled: !_busy,
            onChanged: (id) => setState(() {
              for (final item in widget.order.items) {
                _locationByItem[item.id] = id;
              }
              _selectionVersion++;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
        ],
        for (final item in widget.order.items) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(item.productName ?? item.productId, style: theme.textTheme.titleSmall),
          Text(
            'Quantity: ${formatQuantity(item.quantityOrdered)}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          _LocationDropdown(
            key: ValueKey('${item.id}-$_selectionVersion'),
            label: 'Reserve from',
            leaves: leaves,
            locations: locations,
            value: _locationByItem[item.id],
            enabled: !_busy,
            onChanged: (id) => setState(() => _locationByItem[item.id] = id),
          ),
        ],
      ],
    );
  }

  bool _allSame() {
    if (_locationByItem.length != widget.order.items.length) return false;
    return _locationByItem.values.toSet().length == 1;
  }
}

/// A location dropdown. Each entry leads with the leaf's own "Name (CODE)"
/// and shows where it sits on a second, muted line — truncating a long path
/// from the right would hide exactly the part that tells locations apart
/// (a warehouse can have dozens of leaves under one long zone name).
class _LocationDropdown extends StatelessWidget {
  const _LocationDropdown({
    super.key,
    required this.label,
    required this.leaves,
    required this.locations,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<WarehouseLocation> leaves;
  final WarehouseLocations locations;
  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      // Entries are two lines tall, so let each size to its content.
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final leaf in leaves)
          DropdownMenuItem(
            value: leaf.id,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locations.leafLabel(leaf), overflow: TextOverflow.ellipsis),
                  if (locations.parentPathLabel(leaf.id).isNotEmpty)
                    Text(
                      locations.parentPathLabel(leaf.id),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
      ],
      // Once chosen, one line: the leaf first so it is never the part cut off.
      selectedItemBuilder: (context) => [
        for (final leaf in leaves)
          Text(
            [locations.leafLabel(leaf), locations.parentPathLabel(leaf.id)].where((s) => s.isNotEmpty).join('  ·  '),
            overflow: TextOverflow.ellipsis,
          ),
      ],
      onChanged: enabled ? (id) => id == null ? null : onChanged(id) : null,
    );
  }
}
