import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_number_field.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import 'lifecycle_failure_panel.dart';

/// The two physical fulfilment steps that record a quantity per line.
enum QuantityStep {
  /// STOCK_RESERVED → PICKING. Default = ordered; must not exceed ordered.
  pick,

  /// PICKING → PACKED. Default = picked; must not exceed picked.
  pack;

  String get title => this == pick ? 'Record picking' : 'Record packing';
  String get fieldLabel => this == pick ? 'Picked quantity' : 'Packed quantity';
  String get limitLabel => this == pick ? 'Ordered' : 'Picked';
  String get buttonLabel => this == pick ? 'Save picking' : 'Save packing';

  /// The most a line may take on this step.
  double maxFor(OrderItem item) => this == pick ? item.quantityOrdered : item.quantityPicked;
}

Future<bool> showQuantityEntryDialog(BuildContext context, {required Order order, required QuantityStep step}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => QuantityEntryDialog(order: order, step: step),
  );
  return result ?? false;
}

class QuantityEntryDialog extends ConsumerStatefulWidget {
  const QuantityEntryDialog({super.key, required this.order, required this.step});

  final Order order;
  final QuantityStep step;

  @override
  ConsumerState<QuantityEntryDialog> createState() => _QuantityEntryDialogState();
}

class _QuantityEntryDialogState extends ConsumerState<QuantityEntryDialog> {
  final _formKey = GlobalKey<FormState>();

  /// Owned HERE (parent state), keyed by order-item id, created once — never
  /// inside a row's build — so typing isn't wiped when the dialog rebuilds
  /// (the recreated-controller bug R3a caught).
  final Map<String, TextEditingController> _controllers = {};

  bool _busy = false;
  LifecycleFailure? _failure;

  TextEditingController _controllerFor(OrderItem item) => _controllers.putIfAbsent(
    item.id,
    // Default to the most the line can take: pick everything ordered, pack
    // everything picked. The user edits DOWN from there.
    () => TextEditingController(text: formatQuantity(widget.step.maxFor(item))),
  );

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validate(OrderItem item, String? text) {
    final value = double.tryParse((text ?? '').trim());
    if (value == null) return 'Enter a quantity';
    if (value < 0) return 'Cannot be negative';
    final max = widget.step.maxFor(item);
    if (value > max) return 'Cannot exceed ${formatQuantity(max)}';
    if (((value * 1000) - (value * 1000).roundToDouble()).abs() > 1e-6) return 'At most 3 decimal places';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final quantities = {
      for (final item in widget.order.items) item.id: double.parse(_controllerFor(item).text.trim()),
    };
    try {
      final api = ref.read(ordersApiProvider);
      if (widget.step == QuantityStep.pick) {
        await api.pick(widget.order.id, pickedQty: quantities);
      } else {
        await api.pack(widget.order.id, packedQty: quantities);
      }
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
    final step = widget.step;

    return AppDialog(
      title: step.title,
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step == QuantityStep.pick
                    ? 'Enter what was physically picked for each line. It can be less than ordered, never more.'
                    : 'Confirm what was packed for each line. It can be less than picked, never more.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final item in widget.order.items) ...[
                Text(item.productName ?? item.productId, style: theme.textTheme.titleSmall),
                Text(
                  '${step.limitLabel}: ${formatQuantity(step.maxFor(item))}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppNumberField(
                  label: step.fieldLabel,
                  controller: _controllerFor(item),
                  allowDecimal: true,
                  enabled: !_busy,
                  helperText: _shortNote(item),
                  validator: (v) => _validate(item, v),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_failure != null) LifecycleFailurePanel(failure: _failure!, order: widget.order),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : step.buttonLabel)),
      ],
    );
  }

  /// A quiet heads-up under a field when it's set below its limit.
  String? _shortNote(OrderItem item) {
    final value = double.tryParse(_controllerFor(item).text.trim());
    if (value == null || value < 0) return null;
    final max = widget.step.maxFor(item);
    if (value >= max) return null;
    final short = formatQuantity(max - value);
    return widget.step == QuantityStep.pick ? 'Short pick — $short below ordered' : '$short below picked';
  }
}
