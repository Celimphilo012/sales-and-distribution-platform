import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/attribute_types_providers.dart';
import '../domain/attribute_type.dart';

/// New / edit attribute type (the prototype's attribute form). New active
/// types appear on the product form automatically; values are descriptive
/// metadata, not variants.
Future<void> showAttributeTypeFormDialog(BuildContext context, {AttributeType? attributeType}) =>
    showNxDialog<void>(context, builder: (_) => _AttributeTypeForm(type: attributeType));

class _AttributeTypeForm extends ConsumerStatefulWidget {
  const _AttributeTypeForm({this.type});

  final AttributeType? type;

  @override
  ConsumerState<_AttributeTypeForm> createState() => _AttributeTypeFormState();
}

class _AttributeTypeFormState extends ConsumerState<_AttributeTypeForm> {
  late final _name = TextEditingController(text: widget.type?.name ?? '');
  late final _code = TextEditingController(text: widget.type?.code ?? '');
  late final _unit = TextEditingController(text: widget.type?.unit ?? '');
  late AttributeDataType _dataType = widget.type?.dataType ?? AttributeDataType.text;
  late bool _active = widget.type?.isActive ?? true;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.type != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _unit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (code.isEmpty) 'code': 'Required',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final api = ref.read(attributeTypesApiProvider);
    final unit = _unit.text.trim();
    try {
      if (_editing) {
        final t = widget.type!;
        await api.update(
          t.id,
          name: _name.text.trim(),
          code: code,
          dataType: _dataType,
          unit: unit,
          isActive: _active && !t.isActive ? true : null,
        );
        if (!_active && t.isActive) await api.deactivate(t.id);
      } else {
        final created = await api.create(name: _name.text.trim(), code: code, dataType: _dataType, unit: unit.isEmpty ? null : unit);
        if (!_active) await api.deactivate(created.id);
      }
      invalidateAttributeTypes(ref);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(_editing ? 'Attribute type updated' : 'Attribute type created', '${_name.text.trim()} · $code');
    } on AppError catch (e) {
      setState(() {
        if (e.message.toLowerCase().contains('code')) {
          _errors['code'] = e.message;
        } else {
          _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: _editing ? 'Edit attribute type' : 'New attribute type',
      sub: 'New active types appear on the product form automatically. Values are descriptive metadata, not variants.',
      body: NxFormGrid(
        children: [
          NxField(
            label: 'Name',
            required: true,
            error: _errors['name'],
            child: NxInput(controller: _name, placeholder: 'Country of origin', error: _errors['name'] != null, autofocus: true),
          ),
          NxField(
            label: 'Code',
            required: true,
            error: _errors['code'],
            child: NxInput(controller: _code, placeholder: 'ORIGIN', error: _errors['code'] != null),
          ),
          NxField(
            label: 'Data type',
            child: Align(
              alignment: Alignment.centerLeft,
              child: NxSeg<AttributeDataType>(
                options: const [(AttributeDataType.text, 'Text', null), (AttributeDataType.number, 'Number', null)],
                value: _dataType,
                onChanged: (v) => setState(() => _dataType = v),
              ),
            ),
          ),
          NxField(
            label: 'Unit',
            hint: 'Shown after number values',
            child: NxInput(controller: _unit, placeholder: 'kg, ml, days…'),
          ),
          NxField(
            label: 'Status',
            child: Align(
              alignment: Alignment.centerLeft,
              child: NxSeg<bool>(
                options: const [(true, 'Active', null), (false, 'Inactive', null)],
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create type'),
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
