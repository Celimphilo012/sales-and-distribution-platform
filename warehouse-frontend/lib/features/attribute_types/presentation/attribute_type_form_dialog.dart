import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/attribute_types_providers.dart';
import '../domain/attribute_type.dart';

/// Create (pass no [attributeType]) or edit (pass [attributeType]) — a
/// small form, a dialog is enough (name + code + data type + unit).
Future<void> showAttributeTypeFormDialog(BuildContext context, {AttributeType? attributeType}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _AttributeTypeFormDialog(attributeType: attributeType),
  );
}

class _AttributeTypeFormDialog extends ConsumerStatefulWidget {
  const _AttributeTypeFormDialog({this.attributeType});

  final AttributeType? attributeType;

  @override
  ConsumerState<_AttributeTypeFormDialog> createState() => _AttributeTypeFormDialogState();
}

class _AttributeTypeFormDialogState extends ConsumerState<_AttributeTypeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _unitController;
  late AttributeDataType _dataType;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.attributeType != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.attributeType?.name ?? '');
    _codeController = TextEditingController(text: widget.attributeType?.code ?? '');
    _unitController = TextEditingController(text: widget.attributeType?.unit ?? '');
    _dataType = widget.attributeType?.dataType ?? AttributeDataType.text;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(attributeTypesApiProvider);
    final unit = _unitController.text.trim();
    try {
      if (_isEditing) {
        await api.update(
          widget.attributeType!.id,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          dataType: _dataType,
          unit: unit.isEmpty ? '' : unit,
        );
      } else {
        await api.create(
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          dataType: _dataType,
          unit: unit.isEmpty ? null : unit,
        );
      }
      invalidateAttributeTypes(ref);
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
      title: _isEditing ? 'Edit attribute type' : 'New attribute type',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Name',
              controller: _nameController,
              hintText: 'e.g. Country of Origin',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Code',
              controller: _codeController,
              hintText: 'e.g. COUNTRY_OF_ORIGIN',
              helperText: 'Unique, stable machine code',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<AttributeDataType>(
              label: 'Data type',
              value: _dataType,
              items: AttributeDataType.values,
              itemLabel: (t) => switch (t) {
                AttributeDataType.text => 'Text',
                AttributeDataType.number => 'Number',
              },
              onChanged: (value) => setState(() => _dataType = value ?? AttributeDataType.text),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Unit (optional)',
              controller: _unitController,
              hintText: 'e.g. kg, cm',
              helperText: 'Shown next to the value, e.g. "0.5 kg"',
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
