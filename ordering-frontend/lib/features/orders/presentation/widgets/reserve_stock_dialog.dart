import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/date_format.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../../warehouse_locations/data/warehouse_locations_providers.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import '../../domain/reservation_proposal.dart';
import 'lifecycle_failure_panel.dart';

/// APPROVED → STOCK_RESERVED — the first action that crosses into the
/// warehouse. The backend PROPOSES where to reserve from (one warehouse,
/// oldest stock first, a line split across locations when needed, only
/// locations that actually hold the stock); the manager reserves it as is,
/// or switches warehouse / adjusts a line's locations first.
///
/// The outcomes stay INSIDE this dialog so nothing is lost:
///  * success              → the dialog closes with `true`;
///  * not enough stock      → the plan shows the shortfall and Reserve stays
///    off; if stock moved since the plan was made, the warehouse refuses the
///    whole reservation (nothing is reserved) and the short lines are shown;
///  * warehouse offline     → a "safe to retry" panel; the order did not move.
Future<bool> showReserveStockDialog(BuildContext context, {required Order order}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReserveStockDialog(order: order),
  );
  return result ?? false;
}

/// The plan for (order id, chosen warehouse id — null = let the backend pick).
final reservationProposalProvider = FutureProvider.autoDispose.family<ReservationProposal, (String, String?)>((
  ref,
  key,
) {
  return ref.watch(ordersApiProvider).reservationProposal(key.$1, warehouseId: key.$2);
});

class ReserveStockDialog extends ConsumerStatefulWidget {
  const ReserveStockDialog({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<ReserveStockDialog> createState() => _ReserveStockDialogState();
}

class _ReserveStockDialogState extends ConsumerState<ReserveStockDialog> {
  /// null = the backend's best warehouse.
  String? _warehouseId;

  /// The editable plan: order item id → (location id → quantity).
  Map<String, Map<String, double>>? _plan;

  /// The proposal [_plan] was seeded from — a new proposal re-seeds it.
  ReservationProposal? _seededFrom;

  /// Bumped on every re-seed so the quantity fields rebuild with the new values.
  int _seedVersion = 0;

  final Set<String> _adjusting = {};
  bool _busy = false;
  LifecycleFailure? _failure;

  (String, String?) get _key => (widget.order.id, _warehouseId);

  void _seed(ReservationProposal proposal) {
    if (identical(proposal, _seededFrom)) return;
    _seededFrom = proposal;
    _plan = {for (final line in proposal.lines) line.orderItemId: Map.of(line.allocations)};
    _adjusting.clear();
    _seedVersion++;
  }

  double _total(String itemId) => (_plan?[itemId]?.values ?? const <double>[]).fold(0, (a, b) => a + b);

  /// null when the line is ready to reserve, else what is wrong with it.
  String? _lineProblem(ProposalLine line) {
    final chosen = _plan?[line.orderItemId] ?? const {};
    for (final option in line.options) {
      final take = chosen[option.locationId] ?? 0;
      if (take > option.available + 0.0005) return '${option.label} has only ${formatQuantity(option.available)}';
    }
    final total = _total(line.orderItemId);
    if ((total - line.quantity).abs() > 0.0005) {
      return 'Locations add up to ${formatQuantity(total)} of ${formatQuantity(line.quantity)}';
    }
    return null;
  }

  Future<void> _reserve(ReservationProposal proposal) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      // What the manager sees is exactly what is reserved (never a re-plan behind their back).
      final allocations = [
        for (final line in proposal.lines)
          for (final entry in _plan![line.orderItemId]!.entries)
            if (entry.value > 0)
              ReserveAllocation(orderItemId: line.orderItemId, locationId: entry.key, quantity: entry.value),
      ];
      await ref.read(ordersApiProvider).reserve(widget.order.id, allocations: allocations);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } on AppError catch (e) {
      if (mounted) setState(() => _failure = classifyLifecycleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshPlan() {
    setState(() {
      _failure = null;
      _seededFrom = null;
    });
    ref.invalidate(reservationProposalProvider(_key));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposalAsync = ref.watch(reservationProposalProvider(_key));
    final proposal = proposalAsync.value;
    if (proposal != null) _seed(proposal);
    final ready =
        proposal != null && proposal.lines.isNotEmpty && proposal.lines.every((line) => _lineProblem(line) == null);

    return AppDialog(
      title: 'Reserve stock',
      maxWidth: 620,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          proposalAsync.when(
            skipLoadingOnRefresh: false,
            loading: () => const LoadingStateView(message: 'Finding stock for this order…'),
            error: (error, stackTrace) => ErrorStateView(
              message: error is AppError ? error.message : 'Could not work out where to reserve from.',
              onRetry: _refreshPlan,
            ),
            data: (proposal) => _planView(context, proposal),
          ),
          if (_failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            LifecycleFailurePanel(
              failure: _failure!,
              order: widget.order,
              // Names the short lines' locations (warehouse › … › leaf) instead of raw ids.
              locations: ref.watch(warehouseLocationsProvider).value,
              onRetry: (_busy || proposal == null) ? null : () => _reserve(proposal),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _refreshPlan,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Re-check stock and plan again'),
              ),
            ),
          ],
          if (proposal != null && !proposal.complete) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              proposal.warehouse == null
                  ? 'None of these products is in stock in any active warehouse, so nothing can be reserved yet.'
                  : 'No single warehouse holds enough for the whole order, so it cannot be reserved yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || !ready) ? null : () => _reserve(proposal),
          child: Text(_busy ? 'Reserving…' : (_failure == null ? 'Reserve stock' : 'Try again')),
        ),
      ],
    );
  }

  Widget _planView(BuildContext context, ReservationProposal proposal) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The oldest stock is reserved first, from one warehouse. Reserve as planned, or adjust a line.',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.md),
        if (proposal.alternatives.length > 1)
          DropdownButtonFormField<String>(
            initialValue: proposal.warehouse?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Warehouse'),
            items: [
              for (final w in proposal.alternatives)
                DropdownMenuItem(
                  value: w.id,
                  child: Text(w.complete == false ? '${w.name} — not enough for the whole order' : w.name),
                ),
            ],
            onChanged: _busy ? null : (id) => setState(() => _warehouseId = id),
          )
        else if (proposal.warehouse != null)
          Text('Warehouse: ${proposal.warehouse!.name}', style: theme.textTheme.titleSmall),
        for (final line in proposal.lines) ...[
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          _lineView(context, proposal, line),
        ],
      ],
    );
  }

  Widget _lineView(BuildContext context, ReservationProposal proposal, ProposalLine line) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final error = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error);
    final adjusting = _adjusting.contains(line.orderItemId);
    final chosen = _plan?[line.orderItemId] ?? const {};
    final problem = _lineProblem(line);
    final byId = {for (final o in line.options) o.locationId: o};

    String stockNote(LocationOption o) => [
      '${formatQuantity(o.available)} available',
      if (o.oldestStockAt != null) 'oldest from ${formatDateTime(o.oldestStockAt!).substring(0, 10)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${line.productName} × ${formatQuantity(line.quantity)}', style: theme.textTheme.titleSmall),
            ),
            if (line.options.isNotEmpty)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        if (!_adjusting.remove(line.orderItemId)) _adjusting.add(line.orderItemId);
                      }),
                child: Text(adjusting ? 'Done' : 'Adjust'),
              ),
          ],
        ),
        if (line.options.isEmpty)
          Text(
            proposal.warehouse == null
                ? 'Not in stock in any active warehouse.'
                : 'Not in stock in ${proposal.warehouse!.name}.',
            style: error,
          )
        else if (!adjusting)
          for (final entry in chosen.entries.where((e) => e.value > 0))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 56, child: Text(formatQuantity(entry.value), style: theme.textTheme.titleSmall)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('from ${byId[entry.key]?.label ?? entry.key}'),
                        if (byId[entry.key] != null) Text(stockNote(byId[entry.key]!), style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            )
        else
          for (final option in line.options)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(option.label),
                        Text(stockNote(option), style: muted),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      key: ValueKey('${line.orderItemId}-${option.locationId}-$_seedVersion'),
                      initialValue: formatQuantity(chosen[option.locationId] ?? 0),
                      enabled: !_busy,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                      decoration: const InputDecoration(labelText: 'Take', isDense: true),
                      onChanged: (text) => setState(() {
                        _plan![line.orderItemId]![option.locationId] = double.tryParse(text) ?? 0;
                      }),
                    ),
                  ),
                ],
              ),
            ),
        if (line.shortBy > 0 && !adjusting && line.options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Short by ${formatQuantity(line.shortBy)} in ${proposal.warehouse?.name ?? 'the warehouse'}',
              style: error,
            ),
          )
        else if (problem != null && (adjusting || line.shortBy == 0))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(problem, style: error),
          ),
      ],
    );
  }
}
