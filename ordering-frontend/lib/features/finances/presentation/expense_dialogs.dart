import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/money_format.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../data/finances_api.dart';
import '../domain/finances.dart';

/// Records one expense. The server is the authority (amount must be above
/// zero, at most 2 decimal places).
Future<bool> showRecordExpenseDialog(BuildContext context) async {
  final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (context) => const _RecordExpenseDialog());
  return result ?? false;
}

class _RecordExpenseDialog extends ConsumerStatefulWidget {
  const _RecordExpenseDialog();

  @override
  ConsumerState<_RecordExpenseDialog> createState() => _RecordExpenseDialogState();
}

class _RecordExpenseDialogState extends ConsumerState<_RecordExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.other;
  DateTime _incurredAt = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _incurredAt, firstDate: DateTime(now.year - 2), lastDate: now, helpText: 'Date the expense was incurred');
    if (picked != null) setState(() => _incurredAt = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final description = _descriptionController.text.trim();
      await ref
          .read(financesApiProvider)
          .recordExpense(category: _category, amount: double.parse(_amountController.text), description: description.isEmpty ? null : description, incurredAt: _incurredAt);
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
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppDialog(
      title: 'Record expense',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdownField<ExpenseCategory>(
              label: 'Category',
              value: _category,
              items: ExpenseCategory.values,
              itemLabel: (c) => c.label,
              onChanged: (c) {
                if (c != null) setState(() => _category = c);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppNumberField(label: 'Amount (E)', controller: _amountController, allowDecimal: true, enabled: !_busy, validator: _validateAmount),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text('Incurred: ${formatDateTime(_incurredAt).substring(0, 10)}', style: theme.textTheme.bodyMedium)),
                TextButton.icon(onPressed: _busy ? null : _pickDate, icon: const Icon(Icons.event_outlined, size: 18), label: const Text('Change date')),
              ],
            ),
            TextFormField(controller: _descriptionController, enabled: !_busy, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Record expense')),
      ],
    );
  }
}

/// Voids an expense: it stays on record, struck through, with the reason.
/// The backend asks for a one-time code; the API client's prompt handles it.
Future<bool> showVoidExpenseDialog(BuildContext context, {required Expense expense}) async {
  final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (context) => _VoidExpenseDialog(expense: expense));
  return result ?? false;
}

class _VoidExpenseDialog extends ConsumerStatefulWidget {
  const _VoidExpenseDialog({required this.expense});

  final Expense expense;

  @override
  ConsumerState<_VoidExpenseDialog> createState() => _VoidExpenseDialogState();
}

class _VoidExpenseDialogState extends ConsumerState<_VoidExpenseDialog> {
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
      await ref.read(financesApiProvider).voidExpense(widget.expense.id, reason: _reasonController.text.trim());
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
    final e = widget.expense;

    return AppDialog(
      title: 'Void expense',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${formatMoney(e.amount)} · ${e.category.label}', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Voiding keeps this expense on record (struck through) and takes it out of totals. You will be asked for a one-time code.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _reasonController,
              enabled: !_busy,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Say why this expense is being voided' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
          onPressed: _busy ? null : _void,
          child: Text(_busy ? 'Voiding…' : 'Void expense'),
        ),
      ],
    );
  }
}
