import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/money_format.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../orders/domain/order.dart';
import '../data/payments_api.dart';
import '../domain/payment.dart';

/// Records one payment. Pre-filled with the balance due; the server is the
/// authority (it refuses overpayment, a missing reference for non-cash, and
/// a future date), and its message is shown as-is if it says no.
Future<bool> showRecordPaymentDialog(BuildContext context, {required Order order, required double balanceDue}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RecordPaymentDialog(order: order, balanceDue: balanceDue),
  );
  return result ?? false;
}

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({required this.order, required this.balanceDue});

  final Order order;
  final double balanceDue;

  @override
  ConsumerState<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _paidAt = DateTime.now();
  bool _paidNow = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.balanceDue.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: 'Date the money was received',
    );
    if (picked == null) return;
    setState(() {
      _paidNow = DateUtils.isSameDay(picked, now);
      // A past day is recorded at midday so time zones can't push it to another date.
      _paidAt = _paidNow ? now : DateTime(picked.year, picked.month, picked.day, 12);
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reference = _referenceController.text.trim();
      final notes = _notesController.text.trim();
      await ref
          .read(paymentsApiProvider)
          .record(
            orderId: widget.order.id,
            amount: double.parse(_amountController.text),
            method: _method,
            reference: reference.isEmpty ? null : reference,
            notes: notes.isEmpty ? null : notes,
            paidAt: _paidNow ? null : _paidAt,
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateAmount(String? raw) {
    final text = raw?.trim() ?? '';
    final value = double.tryParse(text);
    if (value == null || value <= 0) return 'Enter an amount above zero';
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return 'Use at most 2 decimal places';
    if (value > widget.balanceDue + 0.005) return 'More than the balance due (${formatMoney(widget.balanceDue)})';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppDialog(
      title: 'Record payment',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.order.orderNumber} · ${widget.order.customer.name} — balance due ${formatMoney(widget.balanceDue)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            AppNumberField(
              label: 'Amount (E)',
              controller: _amountController,
              allowDecimal: true,
              enabled: !_busy,
              validator: _validateAmount,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<PaymentMethod>(
              label: 'Method',
              value: _method,
              items: PaymentMethod.values,
              itemLabel: (m) => m.label,
              onChanged: (m) {
                if (m != null) setState(() => _method = m);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _referenceController,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _method.needsReference ? 'Reference (required)' : 'Reference (optional)',
                hintText: _method.referenceHint,
              ),
              validator: (v) => _method.needsReference && (v == null || v.trim().isEmpty)
                  ? 'Enter the ${_method.referenceHint.toLowerCase()}'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _paidNow ? 'Received: now' : 'Received: ${formatDateTime(_paidAt).substring(0, 10)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: const Text('Change date'),
                ),
              ],
            ),
            TextFormField(
              controller: _notesController,
              enabled: !_busy,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Record payment')),
      ],
    );
  }
}

/// Voids a payment: it stays on record, struck through, with the reason.
/// The backend asks for a one-time code; the API client's prompt handles it.
Future<bool> showVoidPaymentDialog(BuildContext context, {required Payment payment}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _VoidPaymentDialog(payment: payment),
  );
  return result ?? false;
}

class _VoidPaymentDialog extends ConsumerStatefulWidget {
  const _VoidPaymentDialog({required this.payment});

  final Payment payment;

  @override
  ConsumerState<_VoidPaymentDialog> createState() => _VoidPaymentDialogState();
}

class _VoidPaymentDialogState extends ConsumerState<_VoidPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _void() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(paymentsApiProvider).voidPayment(widget.payment.id, reason: _reasonController.text.trim());
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.payment;

    return AppDialog(
      title: 'Void payment',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${formatMoney(p.amount)} · ${p.method.label}${p.reference != null ? ' · Ref ${p.reference}' : ''}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Voiding keeps this payment on record (struck through) and takes it off the amount paid. Use it for a '
              'mistake, or after the money was returned to the customer. You will be asked for a one-time code.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _reasonController,
              enabled: !_busy,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Say why this payment is being voided' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
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
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _void,
          child: Text(_busy ? 'Voiding…' : 'Void payment'),
        ),
      ],
    );
  }
}
