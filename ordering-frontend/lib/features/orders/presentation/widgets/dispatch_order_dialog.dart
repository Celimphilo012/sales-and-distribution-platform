import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import 'lifecycle_failure_panel.dart';

/// READY_FOR_DISPATCH → DISPATCHED or PARTIALLY_FULFILLED — the second action
/// that crosses into the warehouse (the stock actually leaves here).
///
/// The dispatch endpoint takes NO quantities: it ships exactly what was
/// packed, and the backend decides the final status from what the warehouse
/// reports as issued. So this dialog only PREVIEWS the expected result — the
/// real outcome is read from the returned order. Resolves to the updated
/// [Order], or null if the user cancelled / it didn't go through.
Future<Order?> showDispatchOrderDialog(BuildContext context, {required Order order}) {
  return showDialog<Order>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DispatchOrderDialog(order: order),
  );
}

class DispatchOrderDialog extends ConsumerStatefulWidget {
  const DispatchOrderDialog({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<DispatchOrderDialog> createState() => _DispatchOrderDialogState();
}

class _DispatchOrderDialogState extends ConsumerState<DispatchOrderDialog> {
  bool _busy = false;
  LifecycleFailure? _failure;

  List<OrderItem> get _shortLines => [
    for (final item in widget.order.items)
      if (item.quantityPacked < item.quantityOrdered) item,
  ];

  bool get _nothingPacked => widget.order.items.every((i) => i.quantityPacked <= 0);

  Future<void> _dispatch() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await ref.read(ordersApiProvider).transition(widget.order.id, OrderAction.dispatch);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(updated);
    } on AppError catch (e) {
      if (mounted) setState(() => _failure = classifyLifecycleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final partial = _shortLines.isNotEmpty;

    return AppDialog(
      title: 'Dispatch order',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The packed quantities leave the warehouse now and are deducted from stock. '
              'Anything packed short of the ordered amount is released back to available.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final item in widget.order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(item.productName ?? item.productId)),
                    Text(
                      'ships ${formatQuantity(item.quantityPacked)} of ${formatQuantity(item.quantityOrdered)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.quantityPacked < item.quantityOrdered ? semantic.warning : null,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (_nothingPacked)
              _Note(
                color: semantic.warningContainer,
                onColor: semantic.onWarningContainer,
                text:
                    'Nothing was packed, so no stock will ship — the whole reservation is released and the '
                    'order becomes Partially fulfilled.',
              )
            else if (partial)
              _Note(
                color: semantic.warningContainer,
                onColor: semantic.onWarningContainer,
                text:
                    'This will mark the order Partially fulfilled: ${_shortLines.length} '
                    '${_shortLines.length == 1 ? 'line ships' : 'lines ship'} less than ordered, and the '
                    'difference is released back to available stock.',
              )
            else
              _Note(
                color: semantic.successContainer,
                onColor: semantic.onSuccessContainer,
                text: 'Every line ships in full — the order becomes Dispatched.',
              ),
            if (_failure != null) ...[
              const SizedBox(height: AppSpacing.md),
              LifecycleFailurePanel(failure: _failure!, order: widget.order, onRetry: _busy ? null : _dispatch),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _dispatch,
          child: Text(_busy ? 'Dispatching…' : (_failure == null ? 'Dispatch' : 'Try again')),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.onColor, required this.text});

  final Color color;
  final Color onColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onColor)),
    );
  }
}
