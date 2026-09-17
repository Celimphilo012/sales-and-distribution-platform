import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';

/// Create (pass [initialWarehouseId] to preselect, e.g. from a
/// warehouse-scoped context) or edit (pass [workstream]) — a small form,
/// a dialog is enough (warehouse + name + code + description).
Future<void> showWorkstreamFormDialog(
  BuildContext context, {
  Workstream? workstream,
  String? initialWarehouseId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WorkstreamFormDialog(workstream: workstream, initialWarehouseId: initialWarehouseId),
  );
}

class _WorkstreamFormDialog extends ConsumerStatefulWidget {
  const _WorkstreamFormDialog({this.workstream, this.initialWarehouseId});

  final Workstream? workstream;
  final String? initialWarehouseId;

  @override
  ConsumerState<_WorkstreamFormDialog> createState() => _WorkstreamFormDialogState();
}

T? _firstOrNull<T>(Iterable<T> iterable) {
  for (final item in iterable) {
    return item;
  }
  return null;
}

class _WorkstreamFormDialogState extends ConsumerState<_WorkstreamFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  String? _warehouseId;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.workstream != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workstream?.name ?? '');
    _codeController = TextEditingController(text: widget.workstream?.code ?? '');
    _descriptionController = TextEditingController(text: widget.workstream?.description ?? '');
    _warehouseId = widget.workstream?.warehouseId ?? widget.initialWarehouseId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_warehouseId == null) {
      setState(() => _error = 'Choose a warehouse.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(workstreamsApiProvider);
    final description = _descriptionController.text.trim();
    try {
      if (_isEditing) {
        await api.update(
          widget.workstream!.id,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          description: description.isEmpty ? null : description,
        );
      } else {
        await api.create(
          warehouseId: _warehouseId!,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          description: description.isEmpty ? null : description,
        );
      }
      invalidateWorkstreams(ref);
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
    final warehousesAsync = ref.watch(warehousesProvider(false));

    return AppDialog(
      title: _isEditing ? 'Edit workstream' : 'New workstream',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditing)
              warehousesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
                data: (warehouses) {
                  final warehouse = _firstOrNull(warehouses.where((w) => w.id == _warehouseId));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Warehouse: ${warehouse?.name ?? widget.workstream!.warehouseId}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: warehousesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(
                    'Could not load warehouses',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  data: (warehouses) => AppDropdownField<String>(
                    label: 'Warehouse',
                    value: _warehouseId,
                    items: [for (final w in warehouses) w.id],
                    itemLabel: (id) => warehouses.firstWhere((w) => w.id == id).name,
                    onChanged: (value) => setState(() => _warehouseId = value),
                    validator: (v) => v == null ? 'Choose a warehouse' : null,
                  ),
                ),
              ),
            AppTextField(
              label: 'Name',
              controller: _nameController,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Code',
              controller: _codeController,
              helperText: 'Unique within this warehouse',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _descriptionController, maxLines: 2),
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
