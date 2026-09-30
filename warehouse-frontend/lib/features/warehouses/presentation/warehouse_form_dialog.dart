import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/warehouses_providers.dart';
import '../domain/warehouse.dart';

/// New / edit warehouse (the prototype's warehouse form). The code is fixed
/// once created; the structure is built next, from Warehouse Structure.
Future<void> showWarehouseFormDialog(BuildContext context, {Warehouse? warehouse}) =>
    showNxDialog<void>(context, builder: (_) => _WarehouseForm(warehouse: warehouse));

class _WarehouseForm extends ConsumerStatefulWidget {
  const _WarehouseForm({this.warehouse});

  final Warehouse? warehouse;

  @override
  ConsumerState<_WarehouseForm> createState() => _WarehouseFormState();
}

class _WarehouseFormState extends ConsumerState<_WarehouseForm> {
  late final _name = TextEditingController(text: widget.warehouse?.name ?? '');
  late final _code = TextEditingController(text: widget.warehouse?.code ?? '');
  late bool _active = widget.warehouse?.isActive ?? true;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.warehouse != null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
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
    final api = ref.read(warehousesApiProvider);
    try {
      String id;
      if (_editing) {
        final w = widget.warehouse!;
        id = w.id;
        await api.update(w.id, name: _name.text.trim(), isActive: _active && !w.isActive ? true : null);
        if (!_active && w.isActive) await api.deactivate(w.id);
      } else {
        id = (await api.create(name: _name.text.trim(), code: code)).id;
        if (!_active) await api.deactivate(id);
      }
      invalidateWarehouses(ref);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      NxToast.ok(
        _editing ? 'Warehouse updated' : 'Warehouse created',
        '${_name.text.trim()} ($code)',
        _editing ? null : NxToastAction('Build structure', () => router.go('${RoutePaths.locations}?warehouseId=$id')),
      );
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
      title: _editing ? 'Edit warehouse' : 'New warehouse',
      sub: 'Build its structure next, from Warehouse Structure.',
      body: NxFormGrid(
        children: [
          NxSpan2(
            child: NxField(
              label: 'Name',
              required: true,
              error: _errors['name'],
              child: NxInput(controller: _name, error: _errors['name'] != null, autofocus: true),
            ),
          ),
          NxField(
            label: 'Code',
            required: true,
            error: _errors['code'],
            child: NxInput(controller: _code, placeholder: 'PTA-01', enabled: !_editing, error: _errors['code'] != null),
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
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create warehouse'),
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
