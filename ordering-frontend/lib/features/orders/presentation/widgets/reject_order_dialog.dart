import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../data/orders_providers.dart';
import '../../domain/order.dart';
import '../../domain/order_lifecycle.dart';
import 'lifecycle_failure_panel.dart';

/// PENDING_APPROVAL → REJECTED. The backend requires a note explaining why
/// (400 without one), so the form insists on it too — but if the server ever
/// rejects the call anyway, its message is shown as-is.
Future<bool> showRejectOrderDialog(BuildContext context, {required Order order}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RejectOrderDialog(order: order),
  );
  return result ?? false;
}

class RejectOrderDialog extends ConsumerStatefulWidget {
  const RejectOrderDialog({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<RejectOrderDialog> createState() => _RejectOrderDialogState();
}

class _RejectOrderDialogState extends ConsumerState<RejectOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  bool _busy = false;
  LifecycleFailure? _failure;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(ordersApiProvider).reject(widget.order.id, note: _noteController.text.trim());
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

    return AppDialog(
      title: 'Reject order',
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rejecting ends this order — it cannot be reopened. The consultant will see your reason in the '
                'status history.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _noteController,
                enabled: !_busy,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Reason (required)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Give a reason for rejecting this order' : null,
              ),
              if (_failure != null) ...[
                const SizedBox(height: AppSpacing.md),
                LifecycleFailurePanel(failure: _failure!, order: widget.order),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _reject,
          child: Text(_busy ? 'Rejecting…' : 'Reject order'),
        ),
      ],
    );
  }
}
