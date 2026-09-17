import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/warehouses_providers.dart';
import '../domain/warehouse.dart';

/// Create (pass no [warehouse]) or edit (pass [warehouse]) — a small form,
/// a dialog is enough (name + code only).
Future<void> showWarehouseFormDialog(BuildContext context, {Warehouse? warehouse}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WarehouseFormDialog(warehouse: warehouse),
  );
}

class _WarehouseFormDialog extends ConsumerStatefulWidget {
  const _WarehouseFormDialog({this.warehouse});

  final Warehouse? warehouse;

  @override
  ConsumerState<_WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends ConsumerState<_WarehouseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.warehouse != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.warehouse?.name ?? '');
    _codeController = TextEditingController(text: widget.warehouse?.code ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(warehousesApiProvider);
    try {
      if (_isEditing) {
        await api.update(widget.warehouse!.id, name: _nameController.text.trim(), code: _codeController.text.trim());
      } else {
        await api.create(name: _nameController.text.trim(), code: _codeController.text.trim());
      }
      invalidateWarehouses(ref);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: _isEditing ? 'Edit warehouse' : 'New warehouse',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Name',
              controller: _nameController,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Code',
              controller: _codeController,
              helperText: 'Unique across all warehouses',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
